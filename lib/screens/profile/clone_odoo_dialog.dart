import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/command_runner.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';
import 'package:odoo_auto_config/services/git_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class CloneOdooDialog extends StatefulWidget {
  final int version;
  final void Function(String sourcePath) onCloned;

  const CloneOdooDialog({
    super.key,
    required this.version,
    required this.onCloned,
  });

  @override
  State<CloneOdooDialog> createState() => _CloneOdooDialogState();
}

class _CloneOdooDialogState extends State<CloneOdooDialog> {
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
        dialogTitle: context.l10n.baseDirectory,
      );
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: context.l10n.baseDirectory,
      );
    }
    if (path != null) setState(() => _baseDir = path!);
  }

  bool get _canClone =>
      !_cloning &&
      _baseDir.isNotEmpty &&
      _folderController.text.trim().isNotEmpty;

  Future<bool> _ensureGit() async {
    if (await GitService.isInstalled()) return true;

    setState(() => _logLines.add('[+] Git not found. Installing...'));
    final exitCode = await GitService.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    });
    return exitCode == 0;
  }

  Future<void> _clone() async {
    final folder = _folderController.text.trim();
    final targetDir = p.join(_baseDir, folder);

    if (await Directory(targetDir).exists()) {
      setState(
        () => _logLines.add('[ERROR] Directory already exists: $targetDir'),
      );
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
        '--branch',
        '$_version.0',
        '--single-branch',
        if (_shallowClone) '--depth',
        if (_shallowClone) '1',
        '--progress',
        'https://github.com/odoo/odoo.git',
        targetDir,
      ];

      final process = await Process.start('git', args, runInShell: true);

      final stderrLines = <String>[];

      // git clone progress goes to stderr
      final stderrDone = process.stderr.transform(utf8.decoder).listen((data) {
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

      final stdoutDone = process.stdout.transform(utf8.decoder).listen((data) {
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
        await GitBranchService.ensureOriginFetchesAllBranches(targetDir);
        await Process.run(
          'git',
          ['fetch', '--prune', '--quiet', 'origin'],
          workingDirectory: targetDir,
          runInShell: true,
        );
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
      title: Row(
        children: [
          Text(context.l10n.cloneOdooTitle),
          const Spacer(),
          AppDialog.closeButton(context, enabled: !_cloning),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.cloneOdooSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
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
                  .map(
                    (v) => DropdownMenuItem(value: v, child: Text('Odoo $v.0')),
                  )
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
              onChanged: _cloning
                  ? null
                  : (v) => setState(() => _shallowClone = v ?? true),
              title: Text(
                context.l10n.shallowClone,
                style: const TextStyle(fontSize: AppFontSize.md),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
            ],
          ],
        ),
      ),
      actions: [
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
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(
              _cloning ? context.l10n.cloning : context.l10n.cloneOdooSource,
            ),
          ),
      ],
    );
  }
}
