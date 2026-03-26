import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../models/venv_info.dart';
import '../services/storage_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Profile> _profiles = [];
  List<VenvInfo> _venvs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profilesJson = await StorageService.loadProfiles();
    final venvsJson = await StorageService.loadRegisteredVenvs();
    setState(() {
      _profiles = profilesJson.map((j) => Profile.fromJson(j)).toList();
      _venvs = venvsJson.map((j) => VenvInfo.fromJson(j)).toList();
      _loading = false;
    });
  }

  Future<void> _createOrEdit([Profile? existing]) async {
    final result = await showDialog<Profile>(
      context: context,
      builder: (ctx) => _ProfileDialog(
        profile: existing,
        venvs: _venvs,
      ),
    );
    if (result != null) {
      await StorageService.addOrUpdateProfile(result.toJson());
      await _load();
    }
  }

  Future<void> _delete(Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Delete "${profile.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.removeProfile(profile.id);
      await _load();
    }
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
              const Icon(Icons.person, size: 28),
              const SizedBox(width: 12),
              Text('Profiles',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _createOrEdit(),
                icon: const Icon(Icons.add),
                label: const Text('New Profile'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Save venv + odoo-bin + settings as a profile for quick project creation.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_profiles.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No profiles yet. Create one to get started.'),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _profiles.length,
                itemBuilder: (context, index) {
                  final p = _profiles[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${p.odooVersion}'),
                      ),
                      title: Text(p.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Venv: ${p.venvPath}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11)),
                          Text('odoo-bin: ${p.odooBinPath}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11)),
                          Text('odoo src: ${p.odooSourcePath}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11)),
                          Text('db: ${p.dbUser}@${p.dbHost}:${p.dbPort}',
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11)),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _createOrEdit(p),
                            icon: const Icon(Icons.edit),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            onPressed: () => _delete(p),
                            icon: const Icon(Icons.delete),
                            color: Colors.red,
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Dialog for create/edit profile ──

class _ProfileDialog extends StatefulWidget {
  final Profile? profile;
  final List<VenvInfo> venvs;

  const _ProfileDialog({this.profile, required this.venvs});

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _dbHostController;
  late final TextEditingController _dbPortController;
  late final TextEditingController _dbUserController;
  late final TextEditingController _dbPasswordController;
  late final TextEditingController _dbSslmodeController;
  String _venvPath = '';
  String _odooBinPath = '';
  String _odooSourcePath = '';
  int _odooVersion = 17;
  bool _addons = true;
  bool _thirdPartyAddons = true;
  bool _configDir = true;

  final _odooVersions = [14, 15, 16, 17, 18];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _dbHostController = TextEditingController(text: p?.dbHost ?? 'localhost');
    _dbPortController = TextEditingController(text: '${p?.dbPort ?? 5432}');
    _dbUserController = TextEditingController(text: p?.dbUser ?? 'odoo');
    _dbPasswordController = TextEditingController(text: p?.dbPassword ?? '');
    _dbSslmodeController = TextEditingController(text: p?.dbSslmode ?? 'prefer');
    _venvPath = p?.venvPath ?? '';
    _odooBinPath = p?.odooBinPath ?? '';
    _odooSourcePath = p?.odooSourcePath ?? '';
    _odooVersion = p?.odooVersion ?? 17;
    _addons = p?.createAddons ?? true;
    _thirdPartyAddons = p?.createThirdPartyAddons ?? true;
    _configDir = p?.createConfigDir ?? true;

    if (_venvPath.isEmpty && widget.venvs.isNotEmpty) {
      _venvPath = widget.venvs.first.path;
    }
  }

  Future<void> _pickOdooBin() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select odoo-bin',
      type: FileType.any,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _odooBinPath = result.files.single.path!);
    }
  }

  Future<void> _pickOdooSource() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Odoo source code directory',
    );
    if (path != null) {
      setState(() => _odooSourcePath = path);
    }
  }

  void _save() {
    if (_nameController.text.isEmpty ||
        _venvPath.isEmpty ||
        _odooBinPath.isEmpty) {
      return;
    }

    final profile = Profile(
      id: widget.profile?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      venvPath: _venvPath,
      odooBinPath: _odooBinPath,
      odooSourcePath: _odooSourcePath,
      odooVersion: _odooVersion,
      createAddons: _addons,
      createThirdPartyAddons: _thirdPartyAddons,
      createConfigDir: _configDir,
      dbHost: _dbHostController.text,
      dbPort: int.tryParse(_dbPortController.text) ?? 5432,
      dbUser: _dbUserController.text,
      dbPassword: _dbPasswordController.text,
      dbSslmode: _dbSslmodeController.text,
    );

    Navigator.pop(context, profile);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dbHostController.dispose();
    _dbPortController.dispose();
    _dbUserController.dispose();
    _dbPasswordController.dispose();
    _dbSslmodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.profile != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Profile' : 'New Profile'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Profile Name',
                  hintText: 'e.g. Odoo 17',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),

              // Venv selector
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue:
                    widget.venvs.any((v) => v.path == _venvPath)
                        ? _venvPath
                        : null,
                decoration: const InputDecoration(
                  labelText: 'Virtual Environment',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: widget.venvs
                    .map((v) => DropdownMenuItem(
                          value: v.path,
                          child: Text(
                            '${v.name} (${v.path})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _venvPath = v);
                },
                hint: const Text('Select venv'),
              ),
              const SizedBox(height: 16),

              // odoo-bin
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller:
                          TextEditingController(text: _odooBinPath),
                      decoration: const InputDecoration(
                        labelText: 'odoo-bin Path',
                        hintText: '/path/to/odoo/odoo-bin',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _pickOdooBin,
                    icon: const Icon(Icons.file_open),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Odoo source directory (for symlink)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller:
                          TextEditingController(text: _odooSourcePath),
                      decoration: const InputDecoration(
                        labelText: 'Odoo Source Code Directory',
                        hintText: '/path/to/odoo (will be symlinked)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _pickOdooSource,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Odoo version
              DropdownButtonFormField<int>(
                initialValue: _odooVersion,
                decoration: const InputDecoration(
                  labelText: 'Odoo Version',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _odooVersions
                    .map((v) => DropdownMenuItem(
                        value: v, child: Text('Odoo $v')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _odooVersion = v);
                },
              ),
              const SizedBox(height: 16),

              // Folder options
              Wrap(
                spacing: 8,
                children: [
                  _chip('addons', _addons,
                      (v) => setState(() => _addons = v)),
                  _chip('third_party_addons', _thirdPartyAddons,
                      (v) => setState(() => _thirdPartyAddons = v)),
                  _chip('config', _configDir,
                      (v) => setState(() => _configDir = v)),
                ],
              ),
              const SizedBox(height: 20),

              // DB Connection
              Text('Database Connection',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _dbHostController,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dbPortController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dbUserController,
                      decoration: const InputDecoration(
                        labelText: 'User',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dbPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        hintText: 'Leave empty to auto-generate',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dbSslmodeController,
                decoration: const InputDecoration(
                  labelText: 'SSL Mode',
                  hintText: 'prefer, disable, require',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed:
              (_nameController.text.isNotEmpty && _odooBinPath.isNotEmpty)
                  ? _save
                  : null,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  Widget _chip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
    );
  }
}
