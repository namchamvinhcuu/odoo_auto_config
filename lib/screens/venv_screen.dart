import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/python_info.dart';
import 'package:odoo_auto_config/models/venv_config.dart';
import 'package:odoo_auto_config/models/venv_info.dart';
import 'package:odoo_auto_config/providers/venv_provider.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/python_checker_service.dart';
import 'package:odoo_auto_config/services/venv_service.dart';
import 'package:odoo_auto_config/widgets/directory_picker_field.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';
import 'package:odoo_auto_config/widgets/status_card.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'venv/install_requirements_dialog.dart';
import 'venv/package_list_dialog.dart';
import 'venv/pip_install_dialog.dart';

class VenvScreen extends ConsumerStatefulWidget {
  const VenvScreen({super.key});

  @override
  ConsumerState<VenvScreen> createState() => _VenvScreenState();
}

class _VenvScreenState extends ConsumerState<VenvScreen>
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPythons();
  }

  Future<void> _loadPythons() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await _checker.detectAll();
    if (!mounted) return;
    setState(() {
      _pythons = results.where((p) => p.hasVenv).toList();
      if (_pythons.isNotEmpty) _selectedPython = _pythons.first;
      _loading = false;
    });
  }

  Future<void> _registerVenv(VenvInfo venv) async {
    await ref.read(venvProvider.notifier).register(venv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.registeredVenv(venv.name))),
      );
    }
  }

  Future<void> _deleteVenv(VenvInfo venv) async {
    bool deleteFiles = false;

    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Text(context.l10n.deleteVenvTitle),
              const Spacer(),
              AppDialog.closeButton(ctx),
            ],
          ),
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
      await ref.read(venvProvider.notifier).remove(venv.path);
    }
  }

  Future<void> _showPackages(VenvInfo venv) async {
    await AppDialog.show(
      context: context,
      builder: (ctx) => PackageListDialog(venvPath: venv.path),
    );
  }

  Future<void> _pipInstallPackage(VenvInfo venv) async {
    await AppDialog.show(
      context: context,
      builder: (ctx) => PipInstallDialog(venvPath: venv.path, venvName: venv.name),
    );
  }

  Future<void> _installRequirements(VenvInfo venv) async {
    String? reqFile;
    if (PlatformService.isWindows) {
      reqFile = await PlatformService.pickFile(
        dialogTitle: 'Select requirements.txt',
        filter: 'Text files (*.txt)|*.txt|All files (*.*)|*.*',
      );
    } else {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select requirements.txt',
        type: FileType.any,
      );
      reqFile = result?.files.single.path;
    }
    if (reqFile == null) return;

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

    AppDialog.show(
      context: context,
      builder: (ctx) => InstallRequirementsDialog(
        venvPath: venv.path,
        requirementsFile: reqFile!,
        venvService: _venvService,
      ),
    );
  }

  Future<void> _renameVenv(VenvInfo venv) async {
    final controller = TextEditingController(text: venv.label);
    final newLabel = await AppDialog.show<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(context.l10n.renameVenv),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
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
      await ref.read(venvProvider.notifier).updateVenv(updated);
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
    final registeredVenvs =
        ref.read(venvProvider).valueOrNull?.registeredVenvs ?? [];
    for (final venv in results) {
      if (venv.isValid && !registeredVenvs.any((v) => v.path == venv.path)) {
        await ref.read(venvProvider.notifier).register(venv);
      }
    }

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
    final venvAsync = ref.watch(venvProvider);
    final isLoading = venvAsync.isLoading;
    final registeredVenvs =
        venvAsync.valueOrNull?.registeredVenvs ?? [];

    if (isLoading && registeredVenvs.isEmpty) {
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
              onPressed: () => ref.read(venvProvider.notifier).reload(),
              icon: const Icon(Icons.refresh),
              tooltip: context.l10n.refresh,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (registeredVenvs.isEmpty)
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
              itemCount: registeredVenvs.length,
              itemBuilder: (context, index) => _buildVenvCard(
                registeredVenvs[index],
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
    final registeredVenvs =
        ref.watch(venvProvider).valueOrNull?.registeredVenvs ?? [];
    final isAlreadyRegistered =
        registeredVenvs.any((v) => v.path == venv.path);

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
