import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/screens/other_projects/import_workspace_dialog.dart';
import 'package:odoo_auto_config/services/command_runner.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';
import 'package:odoo_auto_config/services/git_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class CloneRepositoryResult {
  final String targetDir;
  final String repoName;
  final String detectedType;
  final String description;

  const CloneRepositoryResult({
    required this.targetDir,
    required this.repoName,
    required this.detectedType,
    required this.description,
  });
}

class CloneRepositoryDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String submitLabel;
  final String? initialBaseDir;
  final bool allowBaseDirPicker;
  final bool showDescription;
  final String baseDirLabel;
  final String baseDirHint;
  final String targetFolderLabel;
  final String initialTargetFolder;

  const CloneRepositoryDialog({
    super.key,
    this.title = 'Clone Repository',
    this.subtitle =
        'Clone a Git repository to your machine and add it to your workspace.',
    this.submitLabel = 'Clone Repo',
    this.initialBaseDir,
    this.allowBaseDirPicker = true,
    this.showDescription = true,
    this.baseDirLabel = 'Base Directory',
    this.baseDirHint = 'Select parent folder',
    this.targetFolderLabel = 'Target Folder (optional)',
    this.initialTargetFolder = '',
  });

  @override
  State<CloneRepositoryDialog> createState() => _CloneRepositoryDialogState();
}

class _CloneRepositoryDialogState extends State<CloneRepositoryDialog> {
  late final TextEditingController _repoUrlController;
  late final TextEditingController _branchController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _targetFolderController;

  String _baseDir = '';
  bool _shallowClone = true;
  bool _cloning = false;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _repoUrlController = TextEditingController();
    _branchController = TextEditingController();
    _descriptionController = TextEditingController();
    _targetFolderController = TextEditingController(
      text: widget.initialTargetFolder,
    );
    _baseDir = widget.initialBaseDir ?? '';
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _branchController.dispose();
    _descriptionController.dispose();
    _targetFolderController.dispose();
    super.dispose();
  }

  String _repoNameFromUrl(String url) {
    var normalized = url.trim();
    if (normalized.isEmpty) return '';
    normalized = normalized.replaceAll('\\', '/');
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final lastSegment = normalized.split('/').last;
    if (lastSegment.isEmpty || lastSegment.contains(':')) return '';
    return lastSegment.endsWith('.git')
        ? lastSegment.substring(0, lastSegment.length - 4)
        : lastSegment;
  }

  Future<void> _pickBaseDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(dialogTitle: 'Base Directory');
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Base Directory',
      );
    }
    if (path != null) {
      setState(() => _baseDir = path!);
    }
  }

  bool get _canClone =>
      !_cloning &&
      _repoUrlController.text.trim().isNotEmpty &&
      _baseDir.isNotEmpty &&
      _repoNameFromUrl(_repoUrlController.text).isNotEmpty &&
      _isSafeTargetFolder(_targetFolderController.text);

  bool _isSafeTargetFolder(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return true;
    if (p.isAbsolute(trimmed)) return false;
    final normalized = p.normalize(trimmed).replaceAll('\\', '/');
    return normalized != '..' &&
        !normalized.startsWith('../') &&
        !normalized.contains('/../');
  }

  Future<bool> _ensureGit() async {
    if (await GitService.isInstalled()) return true;

    setState(() => _logLines.add('[+] Git not found. Installing...'));
    final exitCode = await GitService.install((line) {
      if (mounted) {
        setState(() => _logLines.add(line));
      }
    });
    return exitCode == 0;
  }

  Future<void> _clone() async {
    final repoUrl = _repoUrlController.text.trim();
    final branch = _branchController.text.trim();
    final folder = _repoNameFromUrl(repoUrl);
    final targetFolder = _targetFolderController.text.trim();
    final targetParentDir = targetFolder.isEmpty
        ? _baseDir
        : p.join(_baseDir, p.normalize(targetFolder));
    final targetDir = p.join(targetParentDir, folder);

    if (!_isSafeTargetFolder(targetFolder)) {
      setState(() {
        _logLines.add(
          '[ERROR] Target folder must be relative and cannot use ".." segments',
        );
      });
      return;
    }

    if (await Directory(targetDir).exists()) {
      setState(
        () => _logLines.add('[ERROR] Directory already exists: $targetDir'),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _cloning = true;
      _logLines.clear();
      _logLines.add('[+] Preparing to clone repository...');
    });
    context.setDialogRunning(true);

    final gitOk = await _ensureGit();
    if (!gitOk) {
      if (mounted) {
        setState(() => _cloning = false);
        context.setDialogRunning(false);
      }
      return;
    }

    final git = await GitService.gitPath;
    final args = [
      'clone',
      if (branch.isNotEmpty) ...['--branch', branch, '--single-branch'],
      if (_shallowClone) ...['--depth', '1'],
      '--progress',
      repoUrl,
      targetDir,
    ];

    setState(() => _logLines.add('[+] Cloning into $targetDir...'));

    try {
      await Directory(targetParentDir).create(recursive: true);
      final process = await Process.start(git, args, runInShell: true);
      final stderrLines = <String>[];

      final stdoutDone = process.stdout.transform(utf8.decoder).listen((data) {
        for (final rawLine in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(rawLine);
          if (cleaned != null && mounted) {
            setState(() => _logLines.add(cleaned));
          }
        }
      }).asFuture();

      final stderrDone = process.stderr.transform(utf8.decoder).listen((data) {
        for (final rawLine in data.split('\n')) {
          final trimmed = rawLine.trim();
          if (trimmed.isNotEmpty) stderrLines.add(trimmed);
          final cleaned = CommandRunner.cleanLine(rawLine);
          if (cleaned != null && mounted) {
            setState(() => _logLines.add(cleaned));
          }
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;
      if (!mounted) return;

      if (exitCode != 0) {
        setState(() {
          for (final line in stderrLines) {
            if (!_logLines.contains(line) && !line.contains('%')) {
              _logLines.add('[ERROR] $line');
            }
          }
          _logLines.add('[ERROR] Clone failed with exit code $exitCode');
          _cloning = false;
        });
        context.setDialogRunning(false);
        return;
      }

      await GitBranchService.ensureOriginFetchesAllBranches(targetDir);
      await Process.run(
        git,
        ['fetch', '--prune', '--quiet', 'origin'],
        workingDirectory: targetDir,
        runInShell: true,
      );

      final type = await WorkspaceImportHelper.detectType(targetDir);
      final result = CloneRepositoryResult(
        targetDir: targetDir,
        repoName: WorkspaceImportHelper.basename(targetDir),
        detectedType: type,
        description: _descriptionController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _logLines.add('');
        _logLines.add('[+] Clone completed successfully!');
        _logLines.add('[+] Path: $targetDir');
        if (type.isNotEmpty) {
          _logLines.add('[+] Detected project type: $type');
        }
        _cloning = false;
      });
      context.setDialogRunning(false);
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _logLines.add('[ERROR] $e');
        _cloning = false;
      });
      context.setDialogRunning(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(widget.title),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: AppDialog.contentMaxHeight(context),
            ),
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _repoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Repository URL',
                  hintText: 'https://github.com/org/repo.git',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                enabled: !_cloning,
                onChanged: (_) => setState(() {}),
              ),
              if (_repoNameFromUrl(_repoUrlController.text).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Repository name: ${_repoNameFromUrl(_repoUrlController.text)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _baseDir),
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: widget.baseDirLabel,
                        hintText: widget.baseDirHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (widget.allowBaseDirPicker) ...[
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filled(
                      onPressed: _cloning ? null : _pickBaseDir,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _targetFolderController,
                decoration: InputDecoration(
                  labelText: widget.targetFolderLabel,
                  hintText: 'addons',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText:
                      _targetFolderController.text.isEmpty ||
                          _isSafeTargetFolder(_targetFolderController.text)
                      ? null
                      : 'Use a relative folder only',
                ),
                enabled: !_cloning,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _branchController,
                      decoration: const InputDecoration(
                        labelText: 'Branch (optional)',
                        hintText: 'main',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      enabled: !_cloning,
                    ),
                  ),
                ],
              ),
              if (widget.showDescription) ...[
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_cloning,
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _shallowClone,
                onChanged: _cloning
                    ? null
                    : (value) => setState(() => _shallowClone = value ?? true),
                title: const Text('Shallow clone (--depth 1, faster download)'),
              ),
              const SizedBox(height: AppSpacing.md),
              LogOutput(lines: _logLines, height: AppDialog.logHeightLg),
            ],
          ),
        ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _canClone ? _clone : null,
          icon: _cloning
              ? const SizedBox(
                  width: AppIconSize.md,
                  height: AppIconSize.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(_cloning ? 'Cloning...' : widget.submitLabel),
        ),
      ],
    );
  }
}
