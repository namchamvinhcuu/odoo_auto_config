import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';
import 'create_pr_dialog.dart';

class SimpleGitCommitDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const SimpleGitCommitDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<SimpleGitCommitDialog> createState() => _SimpleGitCommitDialogState();
}

class _SimpleGitCommitDialogState extends State<SimpleGitCommitDialog> {
  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  bool _running = false;
  bool _loading = true;
  bool _done = false;
  bool _pushAfterCommit = true;
  String _currentBranch = '';

  /// Each entry: {'status': 'M', 'file': 'path/to/file', 'selected': true}
  List<Map<String, dynamic>> _changedFiles = [];

  bool get _isMainBranch =>
      _currentBranch == 'main' || _currentBranch == 'master';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _addLine(String line) {
    if (line.contains('\r')) line = line.split('\r').last;
    if (line.trim().isEmpty) return;
    setState(() => _logLines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      // Detect current branch
      final branchResult = await Process.run(
        'git',
        ['branch', '--show-current'],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      if (mounted && branchResult.exitCode == 0) {
        _currentBranch = (branchResult.stdout as String).trim();
      }

      final result = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      if (!mounted) return;
      final output = (result.stdout as String).trimRight();
      if (output.isEmpty) {
        // Kiểm tra xem git có lỗi không
        final stderr = (result.stderr as String).trim();
        if (stderr.isNotEmpty) {
          _addLine('\x1B[0;31m[-] $stderr\x1B[0m');
        }
        setState(() {
          _changedFiles = [];
          _loading = false;
        });
        return;
      }
      final files = <Map<String, dynamic>>[];
      for (final line in output.split('\n')) {
        if (line.length < 4) continue;
        // git status --porcelain format: XY filename (XY = 2 chars, then space, then filename)
        final status = line.substring(0, 2).trim();
        var file = line.substring(3);
        if (status.isEmpty || file.isEmpty) continue;
        // Handle renames: "old -> new"
        if (file.contains(' -> ')) file = file.split(' -> ').last;
        files.add({'status': status, 'file': file, 'selected': true});
      }
      setState(() {
        _changedFiles = files;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _addLine('\x1B[0;31m[-] $e\x1B[0m');
      }
    }
  }

  int get _selectedCount =>
      _changedFiles.where((f) => f['selected'] == true).length;

  bool get _canCommit =>
      !_running &&
      !_loading &&
      !_done &&
      _selectedCount > 0 &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _commit() async {
    setState(() => _running = true);

    final selectedFiles = _changedFiles
        .where((f) => f['selected'] == true)
        .toList();
    final filePaths = selectedFiles.map((f) => f['file'] as String).toList();
    final message = _messageController.text.trim();

    try {
      // git add files one by one
      _addLine('\x1B[0;34m> git add (${filePaths.length} files)\x1B[0m');
      for (final file in filePaths) {
        final addResult = await Process.run(
          'git',
          ['add', '--', file],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );
        if (addResult.exitCode != 0) {
          _addLine('\x1B[0;31m[-] git add failed for: $file\x1B[0m');
          if ((addResult.stderr as String).trim().isNotEmpty) {
            _addLine((addResult.stderr as String).trim());
          }
          if (mounted) setState(() => _running = false);
          return;
        }
      }

      // git commit -m "message"
      _addLine('\x1B[0;34m> git commit -m "$message"\x1B[0m');
      final commitProcess = await Process.start(
        'git',
        ['commit', '-m', message],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      commitProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      commitProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      final commitExit = await commitProcess.exitCode;
      if (!mounted) return;

      if (commitExit != 0) {
        _addLine(
          '\x1B[0;31m[-] ${context.l10n.gitCommitFailed(commitExit)}\x1B[0m',
        );
        setState(() => _running = false);
        return;
      }
      _addLine('\x1B[0;32m[+] ${context.l10n.gitCommitDone}\x1B[0m');

      // Optional push
      if (_pushAfterCommit) {
        _addLine('\x1B[0;34m> git push\x1B[0m');
        final pushProcess = await Process.start(
          'git',
          ['push'],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );
        pushProcess.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (mounted) _addLine(line);
            });
        pushProcess.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              if (mounted) _addLine(line);
            });
        final pushExit = await pushProcess.exitCode;
        if (!mounted) return;
        if (pushExit == 0) {
          _addLine('\x1B[0;32m[+] Push done\x1B[0m');
        } else {
          _addLine('\x1B[0;31m[-] Push failed (exit $pushExit)\x1B[0m');
        }
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'M':
        return const Color(0xFFE5E510); // yellow
      case 'A':
        return const Color(0xFF0DBC79); // green
      case 'D':
        return const Color(0xFFCD3131); // red
      case '??':
        return Colors.grey;
      case 'R':
        return const Color(0xFF2472C8); // blue
      default:
        return Colors.grey.shade300;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _changedFiles.isNotEmpty &&
        _changedFiles.every((f) => f['selected'] == true);

    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitCommitTitle(widget.projectName)),
          const Spacer(),
          IconButton(
            onPressed: (_running || _loading)
                ? null
                : () {
                    setState(() {
                      _done = false;
                      _logLines.clear();
                    });
                    _loadStatus();
                  },
            icon: const Icon(Icons.refresh, color: Colors.white, size: AppIconSize.md),
            tooltip: context.l10n.refresh,
            style: IconButton.styleFrom(
              backgroundColor: (_running || _loading) ? Colors.grey : GitActionColors.refresh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppDialog.closeButton(context, enabled: !_running),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              )
            else if (_changedFiles.isEmpty && _logLines.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    context.l10n.gitCommitNoChanges,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ] else ...[
              // File list with checkboxes
              if (_changedFiles.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      context.l10n.gitStagedFiles(_selectedCount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: (_running || _done)
                          ? null
                          : () {
                              setState(() {
                                final newVal = !allSelected;
                                for (final f in _changedFiles) {
                                  f['selected'] = newVal;
                                }
                              });
                            },
                      icon: Icon(
                        allSelected ? Icons.deselect : Icons.select_all,
                        size: AppIconSize.md,
                      ),
                      label: Text(
                        allSelected
                            ? context.l10n.gitDeselectAll
                            : context.l10n.gitSelectAll,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: AppDialog.listHeight),
                    decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade600),
                    borderRadius: AppRadius.mediumBorderRadius,
                  ),
                  child: ListView.builder(
                    itemCount: _changedFiles.length,
                    itemBuilder: (ctx, i) {
                      final f = _changedFiles[i];
                      final status = f['status'] as String;
                      final file = f['file'] as String;
                      final selected = f['selected'] as bool;
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        onChanged: (_running || _done)
                            ? null
                            : (v) => setState(
                                () => _changedFiles[i]['selected'] = v!,
                              ),
                        title: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$status  ',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: _statusColor(status),
                                  fontSize: AppFontSize.md,
                                ),
                              ),
                              TextSpan(
                                text: file,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.md,
                                ),
                              ),
                            ],
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Commit message
                TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    labelText: context.l10n.gitCommitMessage,
                    hintText: context.l10n.gitCommitMessageHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 8,
                  minLines: 3,
                  enabled: !_running && !_done,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Push checkbox + commit button
                Row(
                  children: [
                    GestureDetector(
                      onTap: (_running || _done)
                          ? null
                          : () => setState(
                              () => _pushAfterCommit = !_pushAfterCommit,
                            ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _pushAfterCommit,
                            onChanged: (_running || _done)
                                ? null
                                : (v) => setState(
                                    () => _pushAfterCommit = v ?? false,
                                  ),
                          ),
                          Text(context.l10n.gitPushAfterCommit),
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _canCommit ? _commit : null,
                      icon: const Icon(Icons.check, size: AppIconSize.md),
                      label: Text(
                        _pushAfterCommit
                            ? context.l10n.gitCommitAndPush
                            : context.l10n.gitCommitOnly,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Log output area
              if (_logLines.isNotEmpty || _running)
                Flexible(
                  child: LogOutput(
                    lines: _logLines,
                    maxHeight: AppDialog.logHeightSm,
                    ansiColors: true,
                    scrollController: _scrollController,
                  ),
                ),
            ],

            if (_running)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),

            // Create PR button after successful commit (non-main branch)
            if (_done && !_isMainBranch)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () {
                      AppDialog.show(
                        context: context,
                        builder: (ctx) => CreatePRDialog(
                          projectName: widget.projectName,
                          projectPath: widget.projectPath,
                          currentBranch: _currentBranch,
                        ),
                      );
                    },
                    icon: const Icon(GitActionIcons.pr, size: AppIconSize.md),
                    label: const Text('Create PR'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GitActionColors.pr,
                    ),
                  ),
                ),
              ),
          ],
          ),
        ),
      ),
    );
  }
}
