import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/models/profile.dart';
import 'package:odoo_auto_config/models/venv_info.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'clone_odoo_dialog.dart';

class ProfileDialog extends StatefulWidget {
  final Profile? profile;
  final List<VenvInfo> venvs;

  const ProfileDialog({super.key, this.profile, required this.venvs});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _dbHostController;
  late final TextEditingController _dbPortController;
  late final TextEditingController _dbUserController;
  late final TextEditingController _dbPasswordController;
  late final TextEditingController _dbSslmodeController;
  ProfileCategory _category = ProfileCategory.odoo;
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
    _dbSslmodeController =
        TextEditingController(text: p?.dbSslmode ?? 'prefer');
    _category = p?.category ?? ProfileCategory.odoo;
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

  void _showCloneOdooDialog() {
    AppDialog.show(
      context: context,
      builder: (ctx) => CloneOdooDialog(
        version: _odooVersion,
        onCloned: (sourcePath) {
          setState(() {
            _odooSourcePath = sourcePath;
            // Auto-detect odoo-bin
            final odooBin = p.join(sourcePath, 'odoo-bin');
            if (File(odooBin).existsSync()) {
              _odooBinPath = odooBin;
            }
          });
        },
      ),
    );
  }

  void _save() {
    if (_nameController.text.isEmpty) return;
    // Odoo profiles require venv + odoo-bin
    if (_category == ProfileCategory.odoo &&
        (_venvPath.isEmpty || _odooBinPath.isEmpty)) {
      return;
    }

    final profile = Profile(
      id: widget.profile?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      category: _category,
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
      title: Row(
        children: [
          Text(isEdit ? context.l10n.editProfile : context.l10n.newProfile),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthXl,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category selector
              SegmentedButton<ProfileCategory>(
                segments: [
                  ButtonSegment(
                    value: ProfileCategory.odoo,
                    label: Text('Odoo'),
                    icon: const Icon(Icons.folder_special),
                  ),
                  ButtonSegment(
                    value: ProfileCategory.general,
                    label: Text(context.l10n.general),
                    icon: const Icon(Icons.workspaces),
                  ),
                ],
                selected: {_category},
                onSelectionChanged: (v) =>
                    setState(() => _category = v.first),
              ),
              const SizedBox(height: AppSpacing.lg),

              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.profileName,
                  hintText: context.l10n.profileNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                autofocus: true,
                onChanged: (_) => setState(() {}),
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

              // ── Odoo-specific fields ──
              if (_category == ProfileCategory.odoo) ...[
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
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: _showCloneOdooDialog,
                      icon: const Icon(Icons.download),
                      label: Text(context.l10n.cloneOdooSource),
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
                          value: v,
                          child: Text(
                              context.l10n.odooVersionLabel(v.toString()))))
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
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed:
              (_nameController.text.isNotEmpty &&
                      (_category == ProfileCategory.general ||
                          _odooBinPath.isNotEmpty))
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
