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

  Future<void> _unregisterVenv(VenvInfo venv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove registration?'),
        content: Text(
            'Remove "${venv.name}" from registered list?\nThis does NOT delete the venv files.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.removeRegisteredVenv(venv.path);
      await _loadRegisteredVenvs();
    }
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
                  IconButton(
                    onPressed: () => _renameVenv(venv),
                    icon: const Icon(Icons.edit),
                    tooltip: 'Rename',
                  ),
                  IconButton(
                    onPressed: () => _unregisterVenv(venv),
                    icon: const Icon(Icons.bookmark_remove),
                    tooltip: 'Unregister',
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
