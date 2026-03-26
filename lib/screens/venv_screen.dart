import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/python_info.dart';
import '../models/venv_config.dart';
import '../models/venv_info.dart';
import '../services/python_checker_service.dart';
import '../services/storage_service.dart';
import '../services/venv_service.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';
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
      // Re-validate each venv
      final valid = await _venvService.validateVenv(info.path);
      venvs.add(VenvInfo(
        path: info.path,
        pythonVersion: info.pythonVersion,
        pipVersion: info.pipVersion,
        isValid: valid,
        label: info.label,
      ));
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
        SnackBar(content: Text('Registered: ${venv.name}')),
      );
    }
  }

  Future<void> _deleteVenv(VenvInfo venv) async {
    bool deleteFiles = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete virtual environment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove "${venv.name}" from registered list?'),
              const SizedBox(height: 4),
              Text(venv.path,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: deleteFiles,
                    onChanged: (v) =>
                        setDialogState(() => deleteFiles = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      'Also delete venv directory from disk',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red),
                child: const Text('Delete')),
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
              SnackBar(content: Text('Deleted: ${venv.path}')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to delete: $e'),
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
    final controller = TextEditingController();
    final packages = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Install Packages'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Venv: ${venv.name}',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Package(s)',
                  hintText: 'e.g. requests flask psycopg2-binary',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Space-separated, supports pip syntax (==, >=)',
                ),
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Install')),
        ],
      ),
    );
    controller.dispose();

    if (packages == null || packages.trim().isEmpty) return;

    _tabController.animateTo(2);

    setState(() {
      _logs.clear();
      _logs.add('[+] pip install ${packages.trim()}');
      _logs.add('    Venv: ${venv.path}');
      _logs.add('');
    });

    // Split packages and install
    final args = packages.trim().split(RegExp(r'\s+'));
    final installResult = await _venvService.installPackage(
      venv.path,
      args.first,
    );

    // For multiple packages, run with full args list
    if (args.length > 1) {
      final pip = '${venv.path}/bin/pip';
      final result = await Process.run(pip, ['install', ...args]);
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
      });
    } else {
      setState(() {
        if (installResult.isSuccess) {
          if (installResult.stdout.isNotEmpty) {
            _logs.addAll(installResult.stdout.split('\n'));
          }
          _logs.add('');
          _logs.add('[+] Package installed successfully!');
        } else {
          _logs.add('[ERROR] Installation failed');
          if (installResult.stderr.isNotEmpty) {
            _logs.addAll(installResult.stderr.split('\n'));
          }
        }
      });
    }
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
          const SnackBar(
            content: Text('File not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Switch to Create New tab to show logs
    _tabController.animateTo(2);

    setState(() {
      _logs.clear();
      _logs.add('[+] Installing packages from: $reqFile');
      _logs.add('    Venv: ${venv.path}');
      _logs.add('    pip: ${venv.path}/bin/pip');
      _logs.add('');
    });

    final installResult = await _venvService.installRequirements(
      venv.path,
      reqFile,
    );

    setState(() {
      if (installResult.isSuccess) {
        if (installResult.stdout.isNotEmpty) {
          _logs.addAll(installResult.stdout.split('\n'));
        }
        _logs.add('');
        _logs.add('[+] Requirements installed successfully!');
      } else {
        _logs.add('[ERROR] Installation failed');
        if (installResult.stderr.isNotEmpty) {
          _logs.addAll(installResult.stderr.split('\n'));
        }
      }
    });
  }

  Future<void> _renameVenv(VenvInfo venv) async {
    final controller = TextEditingController(text: venv.label);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename venv'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'e.g. Odoo 17 Production',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Save')),
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
      _logs.add('    Target: $_targetDir/${_venvNameController.text}');
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: 28),
              const SizedBox(width: 12),
              Text(
                'Virtual Environments',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.bookmark), text: 'Registered'),
              Tab(icon: Icon(Icons.search), text: 'Scan'),
              Tab(icon: Icon(Icons.add_circle), text: 'Create New'),
            ],
          ),
          const SizedBox(height: 16),
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
                'Saved virtual environments for quick access.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ),
            IconButton.filled(
              onPressed: _loadRegisteredVenvs,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_registeredVenvs.isEmpty)
          const Expanded(
            child: Center(
              child: StatusCard(
                title: 'No registered venvs',
                subtitle:
                    'Create a new venv or scan & register existing ones.',
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
          'Scan a directory to find existing virtual environments.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DirectoryPickerField(
                label: 'Scan Directory',
                value: _scanDir,
                onChanged: (v) => setState(() => _scanDir = v),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed:
                  (_scanning || _scanDir.isEmpty) ? null : _scanForVenvs,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Scanning...' : 'Scan'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_scanning)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning for virtual environments...'),
                ],
              ),
            ),
          )
        else if (_foundVenvs.isEmpty && _scanDir.isNotEmpty)
          const Expanded(
            child: Center(
              child: StatusCard(
                title: 'No virtual environments found',
                subtitle:
                    'Try scanning a different directory or increase depth.',
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
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  venv.isValid ? Icons.check_circle : Icons.error,
                  color: venv.isValid ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    venv.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (venv.isValid && venv.pythonVersion.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.code, size: 16),
                    label: Text('Python ${venv.pythonVersion}'),
                  ),
                // Actions
                if (showRegister && !isAlreadyRegistered)
                  IconButton(
                    onPressed: () => _registerVenv(venv),
                    icon: const Icon(Icons.bookmark_add),
                    tooltip: 'Register this venv',
                  ),
                if (showRegister && isAlreadyRegistered)
                  const Chip(
                    avatar: Icon(Icons.bookmark, size: 16),
                    label: Text('Registered'),
                  ),
                if (showRemove) ...[
                  if (venv.isValid) ...[
                    IconButton(
                      onPressed: () => _showPackages(venv),
                      icon: const Icon(Icons.list_alt),
                      tooltip: 'List installed packages',
                    ),
                    IconButton(
                      onPressed: () => _pipInstallPackage(venv),
                      icon: const Icon(Icons.add_box),
                      tooltip: 'pip install package',
                    ),
                    IconButton(
                      onPressed: () => _installRequirements(venv),
                      icon: const Icon(Icons.install_desktop),
                      tooltip: 'Install requirements.txt',
                    ),
                  ],
                  IconButton(
                    onPressed: () => _renameVenv(venv),
                    icon: const Icon(Icons.edit),
                    tooltip: 'Rename',
                  ),
                  IconButton(
                    onPressed: () => _deleteVenv(venv),
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete',
                    color: Colors.red,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              venv.path,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
            if (venv.pipVersion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.inventory_2, size: 16),
                    label: Text('pip ${venv.pipVersion}'),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    avatar: Icon(
                      venv.isValid ? Icons.check : Icons.close,
                      size: 16,
                      color: venv.isValid ? Colors.green : Colors.red,
                    ),
                    label: Text(venv.isValid ? 'Valid' : 'Broken'),
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
          'Create a Python virtual environment for your Odoo project.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
        ),
        const SizedBox(height: 16),

        // Python selector
        DropdownButtonFormField<PythonInfo>(
          initialValue: _selectedPython,
          decoration: const InputDecoration(
            labelText: 'Python Version',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _pythons
              .map((p) => DropdownMenuItem(
                    value: p,
                    child:
                        Text('Python ${p.version} (${p.executablePath})'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedPython = v),
          hint: const Text('No Python with venv support found'),
        ),
        const SizedBox(height: 16),

        // Target directory
        DirectoryPickerField(
          label: 'Target Directory',
          value: _targetDir,
          onChanged: (v) => setState(() => _targetDir = v),
        ),
        const SizedBox(height: 16),

        // Venv name
        TextField(
          controller: _venvNameController,
          decoration: const InputDecoration(
            labelText: 'Virtual Environment Name',
            border: OutlineInputBorder(),
            isDense: true,
            hintText: 'venv',
          ),
        ),
        const SizedBox(height: 20),

        // Create button
        FilledButton.icon(
          onPressed:
              (_creating || _selectedPython == null || _targetDir.isEmpty)
                  ? null
                  : _createVenv,
          icon: _creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add_circle),
          label: Text(_creating ? 'Creating...' : 'Create Venv'),
        ),
        const SizedBox(height: 20),

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

    final pip = '${widget.venvPath}/bin/pip';
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
          const SizedBox(width: 8),
          const Expanded(child: Text('Installed Packages')),
          if (!_loading)
            Text('${_all.length} packages',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search packages...',
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
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                    child: Text('Error: $_error',
                        style: const TextStyle(color: Colors.red))),
              )
            else ...[
              // Table header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text('Package',
                            style:
                                TextStyle(fontWeight: FontWeight.bold))),
                    Expanded(
                        child: Text('Version',
                            style:
                                TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              // Table body
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(child: Text('No packages found.'))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final pkg = _filtered[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
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
                                          fontSize: 13)),
                                ),
                                Expanded(
                                  child: Text(pkg.version,
                                      style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 13,
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
            child: const Text('Close')),
      ],
    );
  }
}

class _PkgInfo {
  final String name;
  final String version;
  const _PkgInfo({required this.name, required this.version});
}
