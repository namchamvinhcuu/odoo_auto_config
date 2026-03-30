import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/profile.dart';
import '../models/venv_info.dart';
import '../services/command_runner.dart';
import '../services/platform_service.dart';
import '../services/storage_service.dart';
import '../widgets/log_output.dart';

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
    _dbSslmodeController = TextEditingController(text: p?.dbSslmode ?? 'prefer');
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
    showDialog(
      context: context,
      builder: (ctx) => _CloneOdooDialog(
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
      title: Text(isEdit ? context.l10n.editProfile : context.l10n.newProfile),
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

// ── Clone Odoo Dialog ──

class _CloneOdooDialog extends StatefulWidget {
  final int version;
  final void Function(String sourcePath) onCloned;

  const _CloneOdooDialog({
    required this.version,
    required this.onCloned,
  });

  @override
  State<_CloneOdooDialog> createState() => _CloneOdooDialogState();
}

class _CloneOdooDialogState extends State<_CloneOdooDialog> {
  late int _version;
  late final TextEditingController _folderController;
  String _baseDir = '';
  bool _shallowClone = true;
  bool _cloning = false;
  bool _cloned = false;
  final List<String> _logLines = [];

  final _versions = [14, 15, 16, 17, 18];

  @override
  void initState() {
    super.initState();
    _version = widget.version;
    _folderController = TextEditingController(text: 'odoo$_version');
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  void _onVersionChanged(int? v) {
    if (v == null) return;
    setState(() {
      _version = v;
      _folderController.text = 'odoo$v';
    });
  }

  Future<void> _pickBaseDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.baseDirectory);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.baseDirectory);
    }
    if (path != null) setState(() => _baseDir = path!);
  }

  bool get _canClone =>
      !_cloning && _baseDir.isNotEmpty && _folderController.text.trim().isNotEmpty;

  Future<bool> _ensureGit() async {
    try {
      final result = await Process.run('git', ['--version'], runInShell: true);
      if (result.exitCode == 0) return true;
    } catch (_) {}

    // Git not found — install it
    setState(() => _logLines.add('[+] Git not found. Installing...'));

    if (Platform.isWindows) {
      final process = await Process.start(
        'winget',
        ['install', '--id', 'Git.Git', '-e', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements'],
        runInShell: true,
      );
      await process.stdout.drain();
      await process.stderr.drain();
      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        setState(() => _logLines.add('[+] Git installed successfully!'));
        return true;
      }
    } else if (Platform.isMacOS) {
      // macOS: xcode-select triggers git install dialog
      final result = await Process.run('xcode-select', ['--install'], runInShell: true);
      if (result.exitCode == 0) {
        setState(() => _logLines.add('[+] Git install triggered. Please complete the dialog and try again.'));
        return false;
      }
    } else {
      final result = await Process.run('pkexec', ['apt', 'install', '-y', 'git'], runInShell: true);
      if (result.exitCode == 0) {
        setState(() => _logLines.add('[+] Git installed successfully!'));
        return true;
      }
    }

    setState(() => _logLines.add('[ERROR] Failed to install Git'));
    return false;
  }

  Future<void> _clone() async {
    final folder = _folderController.text.trim();
    final targetDir = p.join(_baseDir, folder);

    if (await Directory(targetDir).exists()) {
      setState(() => _logLines.add('[ERROR] Directory already exists: $targetDir'));
      return;
    }

    setState(() {
      _cloning = true;
      _logLines.clear();
    });

    // Check/install git first
    final gitOk = await _ensureGit();
    if (!gitOk) {
      setState(() => _cloning = false);
      return;
    }

    setState(() {
      _logLines.add('[+] Cloning Odoo $_version.0 into $targetDir...');
    });

    try {
      final args = [
        'clone',
        '--branch', '$_version.0',
        '--single-branch',
        if (_shallowClone) '--depth', if (_shallowClone) '1',
        '--progress',
        'https://github.com/odoo/odoo.git',
        targetDir,
      ];

      final process = await Process.start('git', args, runInShell: true);

      final stderrLines = <String>[];

      // git clone progress goes to stderr
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .listen((data) {
        if (!mounted) return;
        for (final line in data.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) stderrLines.add(trimmed);
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned != null) {
            setState(() => _logLines.add(cleaned));
          }
        }
      }).asFuture();

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        if (!mounted) return;
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned != null) {
            setState(() => _logLines.add(cleaned));
          }
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (!mounted) return;

      if (exitCode == 0) {
        setState(() {
          _logLines.add('');
          _logLines.add('[+] Odoo $_version.0 cloned successfully!');
          _logLines.add('[+] Path: $targetDir');
          _cloning = false;
          _cloned = true;
        });
        widget.onCloned(targetDir);
      } else {
        setState(() {
          // Show raw error lines that cleanLine may have filtered
          for (final line in stderrLines) {
            if (!_logLines.contains(line) && !line.contains('%')) {
              _logLines.add('[ERROR] $line');
            }
          }
          _logLines.add('[ERROR] Clone failed with exit code $exitCode');
          _cloning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _logLines.add('[ERROR] $e');
          _cloning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.cloneOdooTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.cloneOdooSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: AppSpacing.lg),
            // Version selector
            DropdownButtonFormField<int>(
              initialValue: _version,
              decoration: InputDecoration(
                labelText: context.l10n.odooVersion,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: _versions
                  .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text('Odoo $v.0')))
                  .toList(),
              onChanged: _cloning ? null : _onVersionChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Base directory
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _baseDir),
                    decoration: InputDecoration(
                      labelText: context.l10n.baseDirectory,
                      hintText: context.l10n.browseToSelect,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  onPressed: _cloning ? null : _pickBaseDir,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            // Folder name
            TextField(
              controller: _folderController,
              decoration: InputDecoration(
                labelText: context.l10n.cloneOdooFolder,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              enabled: !_cloning,
            ),
            const SizedBox(height: AppSpacing.md),
            // Shallow clone option
            CheckboxListTile(
              value: _shallowClone,
              onChanged: _cloning ? null : (v) => setState(() => _shallowClone = v ?? true),
              title: Text(context.l10n.shallowClone,
                  style: const TextStyle(fontSize: AppFontSize.md)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LogOutput(lines: _logLines, height: 200),
            ],
          ],
        ),
      ),
      actions: [
        if (!_cloned)
          TextButton(
            onPressed: _cloning ? null : () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        if (_cloned)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text(context.l10n.close),
          )
        else
          FilledButton.icon(
            onPressed: _canClone ? _clone : null,
            icon: _cloning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_cloning
                ? context.l10n.cloning
                : context.l10n.cloneOdooSource),
          ),
      ],
    );
  }
}
