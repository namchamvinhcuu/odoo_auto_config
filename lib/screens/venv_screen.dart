import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/python_info.dart';
import '../models/venv_config.dart';
import '../models/venv_info.dart';
import '../services/python_checker_service.dart';
import '../services/storage_service.dart';
import '../services/platform_service.dart';
import '../services/venv_service.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';
import '../l10n/l10n_extension.dart';
import '../widgets/status_card.dart';

class VenvScreen extends StatefulWidget {
  const VenvScreen({super.key});

  @override
  State<VenvScreen> createState() => _VenvScreenState();
}

class _VenvScreenState extends State<VenvScreen>
    with SingleTickerProviderStateMixin {
  final _checker = PythonCheckerService();
  final _venvService = VenvService();
  final _venvNameController = TextEditingController(text: 'venv');
  final _logs = <String>[];

  late final TabController _tabController;

  List<PythonInfo> _pythons = [];
  PythonInfo? _selectedPython;
  String _targetDir = '';
  bool _loading = false;
  bool _creating = false;

  // Scan existing venvs
  String _scanDir = '';
  List<VenvInfo> _foundVenvs = [];
  bool _scanning = false;

  // Registered venvs
  List<VenvInfo> _registeredVenvs = [];
  bool _loadingRegistered = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPythons();
    _loadRegisteredVenvs();
  }

  Future<void> _loadPythons() async {
    setState(() => _loading = true);
    final results = await _checker.detectAll();
    setState(() {
      _pythons = results.where((p) => p.hasVenv).toList();
      if (_pythons.isNotEmpty) _selectedPython = _pythons.first;
      _loading = false;
    });
  }

  Future<void> _loadRegisteredVenvs() async {
    setState(() => _loadingRegistered = true);
    final saved = await StorageService.loadRegisteredVenvs();
    final List<VenvInfo> venvs = [];
    for (final json in saved) {
      final info = VenvInfo.fromJson(json);
      // Re-inspect to get fresh python/pip version
      final inspected = await _venvService.inspectVenv(info.path);
      if (inspected != null) {
        venvs.add(VenvInfo(
          path: inspected.path,
          pythonVersion: inspected.pythonVersion,
          pipVersion: inspected.pipVersion,
          isValid: inspected.isValid,
          label: info.label,
        ));
      } else {
        venvs.add(VenvInfo(
          path: info.path,
          pythonVersion: info.pythonVersion,
          pipVersion: info.pipVersion,
          isValid: false,
          label: info.label,
        ));
      }
    }
    setState(() {
      _registeredVenvs = venvs;
      _loadingRegistered = false;
    });
  }

  Future<void> _registerVenv(VenvInfo venv) async {
    await StorageService.addRegisteredVenv(venv.toJson());
    await _loadRegisteredVenvs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.registeredVenv(venv.name))),
      );
    }
  }

  Future<void> _deleteVenv(VenvInfo venv) async {
    bool deleteFiles = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.l10n.deleteVenvTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.deleteVenvConfirm(venv.name)),
              const SizedBox(height: AppSpacing.xs),
              Text(venv.path,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.sm,
                      color: Colors.grey.shade500)),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Checkbox(
                    value: deleteFiles,
                    onChanged: (v) =>
                        setDialogState(() => deleteFiles = v ?? false),
                  ),
                  Expanded(
                    child: Text(
                      context.l10n.alsoDeleteVenvFromDisk,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red),
                child: Text(context.l10n.delete)),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (deleteFiles) {
        try {
          final dir = Directory(venv.path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.deletedPath(venv.path))),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.failedToDelete(e.toString())),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      await StorageService.removeRegisteredVenv(venv.path);
      await _loadRegisteredVenvs();
    }
  }

  Future<void> _showPackages(VenvInfo venv) async {
    await showDialog(
      context: context,
      builder: (ctx) => _PackageListDialog(venvPath: venv.path),
    );
  }

  Future<void> _pipInstallPackage(VenvInfo venv) async {
    await showDialog(
      context: context,
      builder: (ctx) => _PipInstallDialog(venvPath: venv.path, venvName: venv.name),
    );
  }

  Future<void> _installRequirements(VenvInfo venv) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select requirements.txt',
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    final reqFile = result.files.single.path!;

    // Verify file exists
    if (!await File(reqFile).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.filePNotFound),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InstallRequirementsDialog(
        venvPath: venv.path,
        requirementsFile: reqFile,
        venvService: _venvService,
      ),
    );
  }

  Future<void> _renameVenv(VenvInfo venv) async {
    final controller = TextEditingController(text: venv.label);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.renameVenv),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: context.l10n.labelField,
            hintText: context.l10n.labelHint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(context.l10n.save)),
        ],
      ),
    );
    controller.dispose();
    if (newLabel != null) {
      final updated = VenvInfo(
        path: venv.path,
        pythonVersion: venv.pythonVersion,
        pipVersion: venv.pipVersion,
        isValid: venv.isValid,
        label: newLabel,
      );
      await StorageService.addRegisteredVenv(updated.toJson());
      await _loadRegisteredVenvs();
    }
  }

  Future<void> _createVenv() async {
    if (_selectedPython == null || _targetDir.isEmpty) return;

    setState(() {
      _creating = true;
      _logs.clear();
      _logs.add('[+] Starting venv creation...');
      _logs.add('    Python: ${_selectedPython!.executablePath}');
      _logs.add('    Target: $_targetDir${Platform.pathSeparator}${_venvNameController.text}');
    });

    final config = VenvConfig(
      pythonPath: _selectedPython!.executablePath,
      targetDirectory: _targetDir,
      venvName: _venvNameController.text,
    );

    final result = await _venvService.createVenv(config);

    setState(() {
      if (result.isSuccess) {
        _logs.add('[+] Virtual environment created successfully!');
        if (result.stdout.isNotEmpty) _logs.add(result.stdout);
      } else {
        _logs.add('[ERROR] Failed to create virtual environment');
        if (result.stderr.isNotEmpty) _logs.add(result.stderr);
      }
      _creating = false;
    });

    if (result.isSuccess) {
      final valid = await _venvService.validateVenv(config.fullPath);
      setState(() {
        if (valid) {
          _logs.add('[+] Venv validated: Python executable found');
          _logs.add('[+] Auto-registering venv...');
        } else {
          _logs.add('[WARN] Venv created but Python executable not found');
        }
      });
      // Auto-register after creation
      final newVenv = VenvInfo(
        path: config.fullPath,
        pythonVersion: _selectedPython!.version,
        pipVersion: '',
        isValid: valid,
        label: _venvNameController.text,
      );
      await _registerVenv(newVenv);
      setState(() {
        _logs.add('[+] Venv registered successfully!');
      });
    }
  }

  Future<void> _scanForVenvs() async {
    if (_scanDir.isEmpty) return;

    setState(() {
      _scanning = true;
      _foundVenvs = [];
    });

    final results = await _venvService.scanForVenvs(_scanDir);

    // Auto-register all found venvs
    for (final venv in results) {
      if (venv.isValid && !_registeredVenvs.any((v) => v.path == venv.path)) {
        await StorageService.addRegisteredVenv(venv.toJson());
      }
    }

    // Reload registered list
    await _loadRegisteredVenvs();

    setState(() {
      _foundVenvs = results;
      _scanning = false;
    });
  }

  @override
  void dispose() {
    _venvNameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(
                context.l10n.venvTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(icon: const Icon(Icons.bookmark), text: context.l10n.registered),
              Tab(icon: const Icon(Icons.search), text: context.l10n.scan),
              Tab(icon: const Icon(Icons.add_circle), text: context.l10n.createNew),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRegisteredTab(),
                _buildScanTab(),
                _buildCreateTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Registered venvs ──
  Widget _buildRegisteredTab() {
    if (_loadingRegistered) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.venvRegisteredSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ),
            IconButton.filled(
              onPressed: _loadRegisteredVenvs,
              icon: const Icon(Icons.refresh),
              tooltip: context.l10n.refresh,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_registeredVenvs.isEmpty)
          Expanded(
            child: Center(
              child: StatusCard(
                title: context.l10n.noRegisteredVenvs,
                subtitle: context.l10n.noRegisteredVenvsSubtitle,
                status: StatusType.info,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _registeredVenvs.length,
              itemBuilder: (context, index) => _buildVenvCard(
                _registeredVenvs[index],
                showRegister: false,
                showRemove: true,
              ),
            ),
          ),
      ],
    );
  }

  // ── Tab 2: Scan existing venvs ──
  Widget _buildScanTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.scanSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: DirectoryPickerField(
                label: context.l10n.scanDirectory,
                value: _scanDir,
                onChanged: (v) => setState(() => _scanDir = v),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed:
                  (_scanning || _scanDir.isEmpty) ? null : _scanForVenvs,
              icon: _scanning
                  ? const SizedBox(
                      width: AppIconSize.md,
                      height: AppIconSize.md,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_scanning ? context.l10n.scanning : context.l10n.scan),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_scanning)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                  Text(context.l10n.scanningVenvs),
                ],
              ),
            ),
          )
        else if (_foundVenvs.isEmpty && _scanDir.isNotEmpty)
          Expanded(
            child: Center(
              child: StatusCard(
                title: context.l10n.noVenvsFound,
                subtitle: context.l10n.noVenvsFoundSubtitle,
                status: StatusType.info,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _foundVenvs.length,
              itemBuilder: (context, index) => _buildVenvCard(
                _foundVenvs[index],
                showRegister: true,
                showRemove: false,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVenvCard(
    VenvInfo venv, {
    bool showRegister = false,
    bool showRemove = false,
  }) {
    final isAlreadyRegistered =
        _registeredVenvs.any((v) => v.path == venv.path);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  venv.isValid ? Icons.check_circle : Icons.error,
                  color: venv.isValid ? Colors.green : Colors.red,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    venv.name,
                    style: const TextStyle(
                      fontSize: AppFontSize.lg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (venv.isValid && venv.pythonVersion.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.code, size: AppIconSize.md),
                    label: Text('Python ${venv.pythonVersion}'),
                  ),
                // Actions
                if (showRegister && !isAlreadyRegistered)
                  IconButton(
                    onPressed: () => _registerVenv(venv),
                    icon: const Icon(Icons.bookmark_add),
                    tooltip: context.l10n.registerThisVenv,
                  ),
                if (showRegister && isAlreadyRegistered)
                  Chip(
                    avatar: const Icon(Icons.bookmark, size: AppIconSize.md),
                    label: Text(context.l10n.registeredChip),
                  ),
                if (showRemove) ...[
                  if (venv.isValid) ...[
                    IconButton(
                      onPressed: () => _showPackages(venv),
                      icon: const Icon(Icons.list_alt),
                      tooltip: context.l10n.listInstalledPackages,
                    ),
                    IconButton(
                      onPressed: () => _pipInstallPackage(venv),
                      icon: const Icon(Icons.add_box),
                      tooltip: context.l10n.pipInstallPackage,
                    ),
                    IconButton(
                      onPressed: () => _installRequirements(venv),
                      icon: const Icon(Icons.install_desktop),
                      tooltip: context.l10n.installRequirements,
                    ),
                  ],
                  IconButton(
                    onPressed: () => _renameVenv(venv),
                    icon: const Icon(Icons.edit),
                    tooltip: context.l10n.rename,
                  ),
                  IconButton(
                    onPressed: () => _deleteVenv(venv),
                    icon: const Icon(Icons.delete),
                    tooltip: context.l10n.delete,
                    color: Colors.red,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              venv.path,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppFontSize.sm,
                color: Colors.grey.shade500,
              ),
            ),
            if (venv.pipVersion.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.inventory_2, size: AppIconSize.md),
                    label: Text('pip ${venv.pipVersion}'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Chip(
                    avatar: Icon(
                      venv.isValid ? Icons.check : Icons.close,
                      size: AppIconSize.md,
                      color: venv.isValid ? Colors.green : Colors.red,
                    ),
                    label: Text(venv.isValid ? context.l10n.valid : context.l10n.broken),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Tab 3: Create new venv ──
  Widget _buildCreateTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.createVenvSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Python selector
        DropdownButtonFormField<PythonInfo>(
          initialValue: _selectedPython,
          decoration: InputDecoration(
            labelText: context.l10n.pythonVersionLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: _pythons
              .map((p) => DropdownMenuItem(
                    value: p,
                    child:
                        Text(context.l10n.pythonVersionDetail(p.version, p.executablePath)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedPython = v),
          hint: Text(context.l10n.noPythonWithVenv),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Target directory
        DirectoryPickerField(
          label: context.l10n.targetDirectory,
          value: _targetDir,
          onChanged: (v) => setState(() => _targetDir = v),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Venv name
        TextField(
          controller: _venvNameController,
          decoration: InputDecoration(
            labelText: context.l10n.venvName,
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: context.l10n.venvNameHint,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Create button
        FilledButton.icon(
          onPressed:
              (_creating || _selectedPython == null || _targetDir.isEmpty)
                  ? null
                  : _createVenv,
          icon: _creating
              ? const SizedBox(
                  width: AppIconSize.md,
                  height: AppIconSize.md,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add_circle),
          label: Text(_creating ? context.l10n.creating : context.l10n.createVenv),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Output
        Expanded(child: LogOutput(lines: _logs)),
      ],
    );
  }
}

// ── Package List Dialog ──

class _PackageListDialog extends StatefulWidget {
  final String venvPath;

  const _PackageListDialog({required this.venvPath});

  @override
  State<_PackageListDialog> createState() => _PackageListDialogState();
}

class _PackageListDialogState extends State<_PackageListDialog> {
  final _searchController = TextEditingController();
  List<_PkgInfo> _all = [];
  List<_PkgInfo> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final pip = PlatformService.venvPip(widget.venvPath);
    try {
      final result = await Process.run(pip, ['list', '--format=json']);
      if (result.exitCode == 0) {
        final list = (jsonDecode(result.stdout.toString()) as List<dynamic>)
            .map((e) => _PkgInfo(
                  name: e['name']?.toString() ?? '',
                  version: e['version']?.toString() ?? '',
                ))
            .toList();
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() {
          _all = list;
          _applyFilter();
          _loading = false;
        });
      } else {
        setState(() {
          _error = result.stderr.toString();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    _filtered = q.isEmpty
        ? _all
        : _all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.list_alt),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(context.l10n.installedPackages)),
          if (!_loading)
            Text(context.l10n.packagesCount(_all.length),
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: AppDialog.heightMd,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.searchPackages,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _applyFilter());
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() => _applyFilter()),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                    child: Text(context.l10n.errorLabel(_error!),
                        style: const TextStyle(color: Colors.red))),
              )
            else ...[
              // Table header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.md)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text(context.l10n.packageHeader,
                            style: const
                                TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(
                        child: Text(context.l10n.versionHeader,
                            style: const
                                TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              // Table body
              Expanded(
                child: _filtered.isEmpty
                    ? Center(child: Text(context.l10n.noPackagesFound))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final pkg = _filtered[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                    color: Colors.grey.withValues(
                                        alpha: 0.2)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(pkg.name,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: AppFontSize.md)),
                                ),
                                Expanded(
                                  child: Text(pkg.version,
                                      style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: AppFontSize.md,
                                          color: Colors.grey.shade500)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close)),
      ],
    );
  }
}

// ── Pip Install Dialog ──

class _PipInstallDialog extends StatefulWidget {
  final String venvPath;
  final String venvName;

  const _PipInstallDialog({required this.venvPath, required this.venvName});

  @override
  State<_PipInstallDialog> createState() => _PipInstallDialogState();
}

class _PipInstallDialogState extends State<_PipInstallDialog> {
  final _controller = TextEditingController();
  final _logs = <String>[];
  bool _installing = false;

  Future<void> _install() async {
    var input = _controller.text.trim();
    if (input.isEmpty) return;

    // Strip "pip install" prefix if user typed it
    input = input.replaceFirst(
        RegExp(r'^pip\s+install\s+', caseSensitive: false), '');
    if (input.isEmpty) return;

    setState(() {
      _installing = true;
      _logs.add('[+] pip install $input');
      _logs.add('    Venv: ${widget.venvPath}');
      _logs.add('');
    });

    final pip = PlatformService.venvPip(widget.venvPath);
    final args = input.split(RegExp(r'\s+'));
    final result = await Process.run(pip, ['install', ...args]);

    if (!mounted) return;

    setState(() {
      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();
      if (result.exitCode == 0) {
        if (stdout.isNotEmpty) _logs.addAll(stdout.split('\n'));
        _logs.add('');
        _logs.add('[+] Packages installed successfully!');
      } else {
        _logs.add('[ERROR] Installation failed');
        if (stderr.isNotEmpty) _logs.addAll(stderr.split('\n'));
      }
      _installing = false;
      _controller.clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.add_box),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(context.l10n.installPackagesTitle(widget.venvName))),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: AppDialog.heightSm,
        child: Column(
          children: [
            Text(widget.venvPath,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppFontSize.xs,
                    color: Colors.grey.shade500)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: context.l10n.packagesField,
                      hintText: context.l10n.packagesFieldHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: !_installing,
                    autofocus: true,
                    onSubmitted: (_) => _install(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _installing ? null : _install,
                  child: _installing
                      ? const SizedBox(
                          width: AppIconSize.md,
                          height: AppIconSize.md,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(context.l10n.install),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppLogColors.terminalBg,
                  borderRadius: AppRadius.mediumBorderRadius,
                  border: Border.all(color: Colors.grey.shade700),
                ),
                child: _logs.isEmpty
                    ? Center(
                        child: Text(context.l10n.outputPlaceholder,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace')),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(AppSpacing.md),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final line = _logs[index];
                          Color color = Colors.grey.shade300;
                          if (line.startsWith('[+]')) {
                            color = AppLogColors.success;
                          } else if (line.startsWith('[ERROR]')) {
                            color = AppLogColors.error;
                          }
                          return Text(line,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.sm,
                                  color: color));
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _installing ? null : () => Navigator.pop(context),
            child: Text(context.l10n.close)),
      ],
    );
  }
}

class _PkgInfo {
  final String name;
  final String version;
  const _PkgInfo({required this.name, required this.version});
}

class _InstallRequirementsDialog extends StatefulWidget {
  final String venvPath;
  final String requirementsFile;
  final VenvService venvService;

  const _InstallRequirementsDialog({
    required this.venvPath,
    required this.requirementsFile,
    required this.venvService,
  });

  @override
  State<_InstallRequirementsDialog> createState() =>
      _InstallRequirementsDialogState();
}

class _InstallRequirementsDialogState
    extends State<_InstallRequirementsDialog> {
  final _logs = <String>[];
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _logs.add('[+] Installing packages from: ${widget.requirementsFile}');
      _logs.add('    Venv: ${widget.venvPath}');
      _logs.add('    pip: ${PlatformService.venvPip(widget.venvPath)}');
      _logs.add('');
    });

    final result = await widget.venvService.installRequirements(
      widget.venvPath,
      widget.requirementsFile,
    );

    if (!mounted) return;

    setState(() {
      if (result.isSuccess) {
        if (result.stdout.isNotEmpty) {
          _logs.addAll(result.stdout.split('\n'));
        }
        _logs.add('');
        _logs.add('[+] Requirements installed successfully!');
      } else {
        _logs.add('[ERROR] Installation failed');
        if (result.stderr.isNotEmpty) {
          _logs.addAll(result.stderr.split('\n'));
        }
      }
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.installRequirements),
      content: SizedBox(
        width: 600,
        child: LogOutput(lines: _logs),
      ),
      actions: [
        if (_running)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
