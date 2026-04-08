import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/postgres_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'create_db_dialog.dart';

class ProjectInfoDialog extends StatefulWidget {
  final ProjectInfo project;
  final String? domain;
  final String domainSuffix;
  final void Function(String dbName) onDbChanged;
  final Future<void> Function(ProjectInfo updated) onSaved;
  final Future<void> Function(ProjectInfo proj) onNginxSetup;
  final Future<void> Function(ProjectInfo proj) onNginxRemove;

  const ProjectInfoDialog({
    super.key,
    required this.project,
    this.domain,
    this.domainSuffix = '',
    required this.onDbChanged,
    required this.onSaved,
    required this.onNginxSetup,
    required this.onNginxRemove,
  });

  @override
  State<ProjectInfoDialog> createState() => _ProjectInfoDialogState();
}

class _ProjectInfoDialogState extends State<ProjectInfoDialog> {
  final _dbNameController = TextEditingController();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _httpPortController;
  late final TextEditingController _lpPortController;
  final _gitOrgController = TextEditingController();
  List<String>? _databases;
  String? _pythonPath;
  String? _odooBinPath;
  String? _confPath;
  String _dbUser = 'odoo';
  bool _editing = false;
  String? _gitScriptPath;
  List<Map<String, dynamic>> _gitAccounts = [];
  Map<String, dynamic>? _selectedGitAccount;
  String _currentScriptToken = '';

  @override
  void initState() {
    super.initState();
    final proj = widget.project;
    _nameController = TextEditingController(text: proj.name);
    _descriptionController = TextEditingController(text: proj.description);
    _httpPortController = TextEditingController(text: '${proj.httpPort}');
    _lpPortController = TextEditingController(text: '${proj.longpollingPort}');
    _dbNameController.text = proj.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    _detectPaths();
    _loadDatabases();
    _loadGitConfig(proj.path);
  }

  @override
  void dispose() {
    _dbNameController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _httpPortController.dispose();
    _lpPortController.dispose();
    _gitOrgController.dispose();
    super.dispose();
  }

  Future<void> _loadGitConfig(String projectPath) async {
    final shPath = p.join(projectPath, 'git-repositories.sh');
    final ps1Path = p.join(projectPath, 'git-repositories.ps1');
    if (File(ps1Path).existsSync()) {
      _gitScriptPath = ps1Path;
    } else if (File(shPath).existsSync()) {
      _gitScriptPath = shPath;
    }

    // Load git accounts from settings
    final settings = await StorageService.loadSettings();
    final accounts = (settings['gitAccounts'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    _gitAccounts = accounts;

    if (_gitScriptPath == null) {
      if (mounted) setState(() {});
      return;
    }

    final content = await File(_gitScriptPath!).readAsString();
    final tokenMatch = RegExp(r'TOKEN\s*=\s*"([^"]*)"').firstMatch(content);
    final orgMatch = RegExp(r'ORG_NAME\s*=\s*"([^"]*)"').firstMatch(content);
    _currentScriptToken = tokenMatch?.group(1) ?? '';

    // Match token to account
    _selectedGitAccount = accounts.where(
        (a) => a['token'] == _currentScriptToken).firstOrNull;

    if (mounted) {
      setState(() {
        _gitOrgController.text = orgMatch?.group(1) ?? '';
      });
    }
  }

  Future<void> _detectPaths() async {
    final projPath = widget.project.path;

    // Try to find odoo.conf and parse DB settings
    for (final candidate in [
      p.join(projPath, 'odoo.conf'),
      p.join(projPath, 'config', 'odoo.conf'),
    ]) {
      if (await File(candidate).exists()) {
        _confPath = candidate;
        // Parse db_user, db_host, db_port from conf
        try {
          final content = await File(candidate).readAsString();
          final userMatch = RegExp(r'^db_user\s*=\s*(.+)$', multiLine: true).firstMatch(content);
          if (userMatch != null) _dbUser = userMatch.group(1)!.trim();
        } catch (_) {}
        break;
      }
    }

    // Try to find python + odoo-bin from .vscode/launch.json
    final launchFile = File(p.join(projPath, '.vscode', 'launch.json'));
    if (await launchFile.exists()) {
      try {
        final content = await launchFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final configs = json['configurations'] as List?;
        if (configs != null && configs.isNotEmpty) {
          final config = configs.first as Map<String, dynamic>;
          _pythonPath = config['python']?.toString();
          _odooBinPath = config['program']?.toString();
          // Resolve ${workspaceFolder}
          if (_odooBinPath != null) {
            _odooBinPath =
                _odooBinPath!.replaceAll(r'${workspaceFolder}', projPath);
          }
        }
      } catch (_) {}
    }

    // Fallback: look for common paths
    _odooBinPath ??= await _findFile([
      p.join(projPath, 'odoo', 'odoo-bin'),
      p.join(projPath, 'odoo-bin'),
    ]);
    _pythonPath ??= await _findFile([
      PlatformService.venvPython(p.join(projPath, 'venv')),
      PlatformService.venvPython(p.join(projPath, '.venv')),
    ]);

    if (mounted) setState(() {});
  }

  Future<void> _loadDatabases() async {
    try {
      final servers = await PostgresService.detectServers();
      final dockerServer = servers
          .where((s) =>
              s.source == PgServerSource.docker &&
              s.containerRunning == true &&
              s.containerName != null)
          .toList();
      if (dockerServer.isEmpty) return;

      final container = dockerServer.first.containerName!;
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
        docker,
        ['exec', container, 'psql', '-U', _dbUser, '-d', 'postgres', '-t', '-A', '-c',
         "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres') ORDER BY datname;"],
        runInShell: true,
      );
      if (result.exitCode == 0 && mounted) {
        setState(() {
          _databases = result.stdout
              .toString()
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<String?> _findFile(List<String> candidates) async {
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }


  void _showCreateDbDialog() {
    AppDialog.show(
      context: context,
      builder: (ctx) => CreateDbDialog(
        defaultName: _dbNameController.text,
        pythonPath: _pythonPath,
        odooBinPath: _odooBinPath,
        confPath: _confPath,
        dbUser: _dbUser,
        projectPath: widget.project.path,
        onCreated: (dbName) {
          setState(() => _dbNameController.text = dbName);
          widget.onDbChanged(dbName);
        },
      ),
    );
  }

  Future<void> _selectDatabase() async {
    // Load databases if not yet loaded
    if (_databases == null || _databases!.isEmpty) {
      await _loadDatabases();
    }
    if (_databases == null || _databases!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noPostgresContainer)),
        );
      }
      return;
    }
    if (!mounted) return;
    final selected = await AppDialog.show<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Database'),
        children: _databases!.map((db) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, db),
          child: Row(
            children: [
              const Icon(Icons.storage, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(db, style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
        )).toList(),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _dbNameController.text = selected);
    await _updateDbFilter(selected);
    widget.onDbChanged(selected);
  }

  Future<void> _updateDbFilter(String dbName) async {
    if (_confPath == null) return;
    try {
      final file = File(_confPath!);
      var content = await file.readAsString();
      final regex = RegExp(r'^dbfilter\s*=.*$', multiLine: true);
      if (regex.hasMatch(content)) {
        content = content.replaceFirst(regex, 'dbfilter = ^$dbName.*\$');
      }
      final dbNameRegex = RegExp(r'^db_name\s*=.*$', multiLine: true);
      if (dbNameRegex.hasMatch(content)) {
        content = content.replaceFirst(dbNameRegex, 'db_name = $dbName');
      }
      await file.writeAsString(content);
    } catch (_) {}
  }

  Future<void> _saveChanges() async {
    final newName = _nameController.text.trim();
    final newDesc = _descriptionController.text.trim();
    final newHttp = int.tryParse(_httpPortController.text) ?? widget.project.httpPort;
    final newLp = int.tryParse(_lpPortController.text) ?? widget.project.longpollingPort;

    // Check port conflict
    final conflict = await StorageService.checkPortConflict(newHttp, newLp, widget.project.path);
    if (conflict != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(conflict), backgroundColor: Colors.red),
      );
      return;
    }

    final updated = ProjectInfo(
      name: newName,
      path: widget.project.path,
      description: newDesc,
      httpPort: newHttp,
      longpollingPort: newLp,
      createdAt: widget.project.createdAt,
    );

    // Update git script if exists
    if (_gitScriptPath != null) {
      final file = File(_gitScriptPath!);
      if (await file.exists()) {
        var content = await file.readAsString();
        final newToken = (_selectedGitAccount?['token'] ?? '').toString();
        final newOrg = _gitOrgController.text.trim();
        if (newToken.isNotEmpty) {
          content = content.replaceFirstMapped(
              RegExp(r'(TOKEN\s*=\s*)"[^"]*"'),
              (m) => '${m[1]}"$newToken"');
        }
        if (newOrg.isNotEmpty) {
          content = content.replaceFirstMapped(
              RegExp(r'(ORG_NAME\s*=\s*)"[^"]*"'),
              (m) => '${m[1]}"$newOrg"');
        }
        await file.writeAsString(content);
      }
    }

    await widget.onSaved(updated);
    if (mounted) {
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.saved)),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final proj = widget.project;

    return AlertDialog(
      title: Row(
        children: [
          Icon(_editing ? Icons.edit : Icons.info_outline),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(_editing ? context.l10n.editProject : proj.name)),
          if (!_editing)
            IconButton(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit),
              tooltip: context.l10n.edit,
            ),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: _editing ? _buildEditView() : _buildInfoView(),
        ),
      ),
      actions: [
        if (_editing)
          FilledButton(
            onPressed: _nameController.text.trim().isNotEmpty ? _saveChanges : null,
            child: Text(context.l10n.save),
          ),
      ],
    );
  }

  Widget _buildInfoView() {
    final proj = widget.project;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(Icons.folder, context.l10n.projectDirectory, proj.path),
        const SizedBox(height: AppSpacing.md),
        _infoRow(Icons.lan, 'HTTP Port', '${proj.httpPort}'),
        const SizedBox(height: AppSpacing.sm),
        _infoRow(Icons.lan, 'Longpolling Port', '${proj.longpollingPort}'),
        const SizedBox(height: AppSpacing.md),
        _infoRow(
          Icons.dns,
          context.l10n.projectInfoDomain,
          widget.domain != null
              ? 'https://${widget.domain}'
              : context.l10n.projectInfoNginxNotSetup,
          valueColor: widget.domain != null ? Colors.green : Colors.orange,
        ),
        _infoRow(
          Icons.storage,
          'Database',
          proj.hasDb ? proj.dbName! : '—',
          valueColor: proj.hasDb ? null : Colors.grey,
        ),
        if (proj.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _infoRow(Icons.description, context.l10n.descriptionOptional,
              proj.description),
        ],

        // Nginx section
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Text('Nginx', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (proj.hasNginx) ...[
          _infoRow(Icons.dns, 'Domain',
              'https://${proj.nginxSubdomain}${widget.domainSuffix}',
              valueColor: Colors.green),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonalIcon(
            onPressed: () => widget.onNginxRemove(proj),
            icon: const Icon(Icons.delete, size: AppIconSize.md),
            label: Text(context.l10n.nginxRemove),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
          ),
        ] else
          FilledButton.icon(
            onPressed: () => widget.onNginxSetup(proj),
            icon: const Icon(Icons.add, size: AppIconSize.md),
            label: Text(context.l10n.nginxSetup),
          ),

        // Database actions
        const SizedBox(height: AppSpacing.lg),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Text('Database', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _showCreateDbDialog(),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.createDatabase),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _selectDatabase,
                icon: const Icon(Icons.list),
                label: const Text('Import Database'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Path (read-only)
        _infoRow(Icons.folder, context.l10n.projectDirectory, widget.project.path),
        const SizedBox(height: AppSpacing.lg),

        // Name
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: context.l10n.projectName,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Description
        TextField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: context.l10n.descriptionOptional,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Ports
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _httpPortController,
                decoration: InputDecoration(
                  labelText: context.l10n.httpPort,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: TextField(
                controller: _lpPortController,
                decoration: InputDecoration(
                  labelText: context.l10n.longpollingPort,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),

        // Git config (if script exists)
        if (_gitScriptPath != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Text('Git Repositories',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          if (_gitAccounts.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _selectedGitAccount?['name'] as String?,
              decoration: const InputDecoration(
                labelText: 'Git Account',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _gitAccounts.map<DropdownMenuItem<String>>((a) {
                final name = (a['name'] ?? '').toString();
                return DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedGitAccount = _gitAccounts
                      .where((a) => a['name'] == v)
                      .firstOrNull;
                });
              },
            )
          else
            Text('No Git accounts configured. Add in Settings > Git.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: AppFontSize.md)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _gitOrgController,
            decoration: InputDecoration(
              labelText: context.l10n.gitOrg,
              hintText: context.l10n.gitOrgHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Colors.grey),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 170,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: AppFontSize.xl)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppFontSize.xl,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
