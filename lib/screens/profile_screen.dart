import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/profile.dart';
import '../models/venv_info.dart';
import '../services/platform_service.dart';
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
        title: Text(context.l10n.deleteProfileTitle),
        content: Text(context.l10n.deleteProfileConfirm(profile.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.delete)),
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
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(context.l10n.profilesTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _createOrEdit(),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.newProfile),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.profilesSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_profiles.isEmpty)
            Expanded(
              child: Center(
                child: Text(context.l10n.profilesEmpty),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _profiles.length,
                itemBuilder: (context, index) {
                  final p = _profiles[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                          Text(context.l10n.venvLabel(p.venvPath),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: AppFontSize.xl)),
                          Text(context.l10n.odooBinLabel(p.odooBinPath),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: AppFontSize.xl)),
                          Text(context.l10n.odooSrcLabel(p.odooSourcePath),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: AppFontSize.xl)),
                          Text(context.l10n.dbLabel(p.dbUser, p.dbHost, p.dbPort.toString()),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: AppFontSize.xl)),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _createOrEdit(p),
                            icon: const Icon(Icons.edit),
                            tooltip: context.l10n.edit,
                          ),
                          IconButton(
                            onPressed: () => _delete(p),
                            icon: const Icon(Icons.delete),
                            color: Colors.red,
                            tooltip: context.l10n.delete,
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
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickFile(
        dialogTitle: context.l10n.selectOdooBin,
      );
    } else {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: context.l10n.selectOdooBin,
        type: FileType.any,
      );
      path = result?.files.single.path;
    }
    if (path != null) {
      setState(() => _odooBinPath = path!);
    }
  }

  Future<void> _pickOdooSource() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
        dialogTitle: context.l10n.selectOdooSourceDirectory,
      );
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: context.l10n.selectOdooSourceDirectory,
      );
    }
    if (path != null) {
      setState(() => _odooSourcePath = path!);
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
      title: Text(isEdit ? context.l10n.editProfile : context.l10n.newProfile),
      content: SizedBox(
        width: AppDialog.widthXl,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.profileName,
                  hintText: context.l10n.profileNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Venv selector
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue:
                    widget.venvs.any((v) => v.path == _venvPath)
                        ? _venvPath
                        : null,
                decoration: InputDecoration(
                  labelText: context.l10n.virtualEnvironment,
                  border: const OutlineInputBorder(),
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
                hint: Text(context.l10n.selectVenv),
              ),
              const SizedBox(height: AppSpacing.lg),

              // odoo-bin
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller:
                          TextEditingController(text: _odooBinPath),
                      decoration: InputDecoration(
                        labelText: context.l10n.odooBinPath,
                        hintText: context.l10n.odooBinPathHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _pickOdooBin,
                    icon: const Icon(Icons.file_open),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Odoo source directory (for symlink)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller:
                          TextEditingController(text: _odooSourcePath),
                      decoration: InputDecoration(
                        labelText: context.l10n.odooSourceDirectory,
                        hintText: context.l10n.odooSourceHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _pickOdooSource,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Odoo version
              DropdownButtonFormField<int>(
                initialValue: _odooVersion,
                decoration: InputDecoration(
                  labelText: context.l10n.odooVersion,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: _odooVersions
                    .map((v) => DropdownMenuItem(
                        value: v, child: Text(context.l10n.odooVersionLabel(v.toString()))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _odooVersion = v);
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // Folder options
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _chip(context.l10n.addons, _addons,
                      (v) => setState(() => _addons = v)),
                  _chip(context.l10n.thirdPartyAddons, _thirdPartyAddons,
                      (v) => setState(() => _thirdPartyAddons = v)),
                  _chip(context.l10n.config, _configDir,
                      (v) => setState(() => _configDir = v)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // DB Connection
              Text(context.l10n.databaseConnection,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _dbHostController,
                      decoration: InputDecoration(
                        labelText: context.l10n.host,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _dbPortController,
                      decoration: InputDecoration(
                        labelText: context.l10n.port,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dbUserController,
                      decoration: InputDecoration(
                        labelText: context.l10n.user,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _dbPasswordController,
                      decoration: InputDecoration(
                        labelText: context.l10n.password,
                        hintText: context.l10n.passwordHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      obscureText: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _dbSslmodeController,
                decoration: InputDecoration(
                  labelText: context.l10n.sslMode,
                  hintText: context.l10n.sslModeHint,
                  border: const OutlineInputBorder(),
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
            child: Text(context.l10n.cancel)),
        FilledButton(
          onPressed:
              (_nameController.text.isNotEmpty && _odooBinPath.isNotEmpty)
                  ? _save
                  : null,
          child: Text(isEdit ? context.l10n.save : context.l10n.create),
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
