import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/postgres_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class CreateDbDialog extends StatefulWidget {
  final String defaultName;
  final String? pythonPath;
  final String? odooBinPath;
  final String? confPath;
  final String dbUser;
  final String projectPath;
  final void Function(String dbName) onCreated;

  const CreateDbDialog({
    super.key,
    required this.defaultName,
    this.pythonPath,
    this.odooBinPath,
    this.confPath,
    required this.dbUser,
    required this.projectPath,
    required this.onCreated,
  });

  @override
  State<CreateDbDialog> createState() => _CreateDbDialogState();
}

class _CreateDbDialogState extends State<CreateDbDialog> {
  late final TextEditingController _nameController;
  String _language = 'en_US';
  bool _demoData = false;
  bool _creating = false;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final dbName = _nameController.text.trim();
    if (dbName.isEmpty) return;

    setState(() {
      _creating = true;
      _logLines.clear();
    });

    void log(String line) {
      if (mounted) setState(() => _logLines.add(line));
    }

    try {
      // Step 1: Create PostgreSQL database via Docker
      log('[+] Creating PostgreSQL database "$dbName"...');
      final servers = await PostgresService.detectServers();
      final dockerServer = servers
          .where((s) =>
              s.source == PgServerSource.docker &&
              s.containerRunning == true &&
              s.containerName != null)
          .toList();

      if (dockerServer.isEmpty) {
        if (!mounted) return;
        log('[ERROR] ${context.l10n.noPostgresContainer}');
        setState(() => _creating = false);
        return;
      }

      final container = dockerServer.first.containerName!;
      final docker = await PlatformService.dockerPath;

      final createResult = await Process.run(
        docker,
        ['exec', container, 'createdb', '-U', widget.dbUser, '--maintenance-db=postgres', dbName],
        runInShell: true,
      );

      if (createResult.exitCode != 0) {
        final err = createResult.stderr.toString().trim();
        if (!err.contains('already exists')) {
          log('[ERROR] $err');
          setState(() => _creating = false);
          return;
        }
        log('[WARN] Database "$dbName" already exists, initializing...');
      } else {
        log('[+] Database "$dbName" created');
      }

      // Step 2: Initialize Odoo
      if (widget.pythonPath == null || widget.odooBinPath == null || widget.confPath == null) {
        log('[+] Database created. Start Odoo to initialize modules.');
        if (widget.pythonPath == null) log('[WARN] Python not found');
        if (widget.odooBinPath == null) log('[WARN] odoo-bin not found');
        if (widget.confPath == null) log('[WARN] odoo.conf not found');
        widget.onCreated(dbName);
        setState(() => _creating = false);
        return;
      }

      log('');
      log('[+] Initializing Odoo database (this may take a few minutes)...');

      final args = [
        widget.odooBinPath!,
        '-c', widget.confPath!,
        '-d', dbName,
        '-i', 'base',
        '--stop-after-init',
        '--load-language=$_language',
        if (!_demoData) '--without-demo=all',
      ];

      final process = await Process.start(
        widget.pythonPath!,
        args,
        runInShell: true,
        workingDirectory: widget.projectPath,
      );

      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) log(line.trim());
        }
      });
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) log(line.trim());
        }
      });

      final exitCode = await process.exitCode;

      if (mounted) {
        if (exitCode == 0) {
          // Update odoo.conf
          if (widget.confPath != null) {
            try {
              final file = File(widget.confPath!);
              var content = await file.readAsString();
              final dbFilterRegex = RegExp(r'^dbfilter\s*=.*$', multiLine: true);
              if (dbFilterRegex.hasMatch(content)) {
                content = content.replaceFirst(dbFilterRegex, 'dbfilter = ^$dbName.*\$');
              }
              final dbNameRegex = RegExp(r'^db_name\s*=.*$', multiLine: true);
              if (dbNameRegex.hasMatch(content)) {
                content = content.replaceFirst(dbNameRegex, 'db_name = $dbName');
              }
              await file.writeAsString(content);
              log('[+] Updated odoo.conf');
            } catch (_) {}
          }
          log('');
          if (mounted) log('[+] ${context.l10n.dbCreated(dbName)}');
          widget.onCreated(dbName);
        } else {
          log('');
          log('[ERROR] Odoo init failed with exit code $exitCode');
        }
        setState(() => _creating = false);
      }
    } catch (e) {
      log('[ERROR] $e');
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.createDatabase),
          const Spacer(),
          AppDialog.closeButton(context, enabled: !_creating),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.projectInfoDbName,
                  hintText: context.l10n.projectInfoDbNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                enabled: !_creating,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _language,
                      decoration: InputDecoration(
                        labelText: context.l10n.language,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'en_US', child: Text('English')),
                        DropdownMenuItem(value: 'vi_VN', child: Text('Tiếng Việt')),
                        DropdownMenuItem(value: 'ko_KR', child: Text('한국어')),
                        DropdownMenuItem(value: 'fr_FR', child: Text('Français')),
                        DropdownMenuItem(value: 'de_DE', child: Text('Deutsch')),
                        DropdownMenuItem(value: 'ja_JP', child: Text('日本語')),
                        DropdownMenuItem(value: 'zh_CN', child: Text('中文(简体)')),
                      ],
                      onChanged: _creating ? null : (v) => setState(() => _language = v!),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilterChip(
                    label: const Text('Demo data'),
                    selected: _demoData,
                    onSelected: _creating ? null : (v) => setState(() => _demoData = v),
                  ),
                ],
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: AppDialog.logHeightLg),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _creating || _nameController.text.trim().isEmpty ? null : _create,
          icon: _creating
              ? const SizedBox(width: AppIconSize.md, height: AppIconSize.md, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(_creating ? context.l10n.creatingDatabase : context.l10n.createDatabase),
        ),
      ],
    );
  }
}
