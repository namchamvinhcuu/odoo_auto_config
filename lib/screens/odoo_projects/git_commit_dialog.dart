import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/widgets/ansi_parser.dart';

class RepoStatus {
  final String name;
  final String path;
  final int changedFiles;
  bool selected;

  RepoStatus({
    required this.name,
    required this.path,
    required this.changedFiles,
  }) : selected = true;
}

class GitCommitDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const GitCommitDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<GitCommitDialog> createState() => _GitCommitDialogState();
}

class _GitCommitDialogState extends State<GitCommitDialog> {
  final List<RepoStatus> _repos = [];
  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  bool _scanning = true;
  bool _running = false;
  bool _done = false;
  bool _pushAfterCommit = true;

  @override
  void initState() {
    super.initState();
    _scanRepos();
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

  Future<void> _scanRepos() async {
    setState(() => _scanning = true);
    try {
      final addonsDir = Directory(p.join(widget.projectPath, 'addons'));
      if (!await addonsDir.exists()) {
        setState(() => _scanning = false);
        return;
      }
      final entries = await addonsDir.list().toList();
      for (final entry in entries) {
        if (entry is! Directory) continue;
        final gitDir = Directory(p.join(entry.path, '.git'));
        if (!await gitDir.exists()) continue;
        final result = await Process.run(
          'git',
          ['status', '--porcelain'],
          workingDirectory: entry.path,
          runInShell: true,
        );
        final output = (result.stdout as String).trim();
        if (output.isEmpty) continue;
        final fileCount = LineSplitter.split(output).length;
        _repos.add(RepoStatus(
          name: p.basename(entry.path),
          path: entry.path,
          changedFiles: fileCount,
        ));
      }
      _repos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) setState(() => _scanning = false);
  }

  int get _selectedCount => _repos.where((r) => r.selected).length;

  bool get _canCommit =>
      !_running &&
      !_scanning &&
      !_done &&
      _selectedCount > 0 &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    final selected = _repos.where((r) => r.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _running = true);
    for (final repo in selected) {
      _addLine('\x1B[0;34m[*] ${repo.name}\x1B[0m');

      // git add -A
      final addResult = await Process.run(
        'git',
        ['add', '-A'],
        workingDirectory: repo.path,
        runInShell: true,
      );
      if (addResult.exitCode != 0) {
        _addLine('\x1B[0;31m[-] git add failed: ${addResult.stderr}\x1B[0m');
        continue;
      }

      // git commit
      final commitResult = await Process.run(
        'git',
        ['commit', '-m', message],
        workingDirectory: repo.path,
        runInShell: true,
      );
      final commitOut = (commitResult.stdout as String).trim();
      if (commitOut.isNotEmpty) _addLine(commitOut);
      if (commitResult.exitCode != 0) {
        final errOut = (commitResult.stderr as String).trim();
        if (errOut.isNotEmpty) _addLine('\x1B[0;31m$errOut\x1B[0m');
        if (mounted) {
          _addLine(
              '\x1B[0;31m[-] ${context.l10n.gitCommitFailed(commitResult.exitCode)}\x1B[0m');
        }
        continue;
      }

      // git push (optional)
      if (_pushAfterCommit) {
        _addLine('\x1B[0;36m[>] Pushing ${repo.name}...\x1B[0m');
        final pushProcess = await Process.start(
          'git',
          ['push'],
          workingDirectory: repo.path,
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
        if (pushExit != 0 && mounted) {
          _addLine('\x1B[0;31m[-] Push failed for ${repo.name}\x1B[0m');
        }
      }

      if (mounted) {
        _addLine('\x1B[0;32m[+] ${repo.name}: ${context.l10n.gitCommitDone}\x1B[0m');
      }
    }
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  void _toggleAll(bool select) {
    setState(() {
      for (final r in _repos) {
        r.selected = select;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitCommitTitle(widget.projectName)),
          const Spacer(),
          AppDialog.closeButton(context, enabled: !_running && !_scanning),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            if (_scanning)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            if (!_scanning && _repos.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  context.l10n.gitNoReposWithChanges,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            if (_repos.isNotEmpty) ...[
              // Select all / Deselect all
              Row(
                children: [
                  TextButton.icon(
                    onPressed: (_running || _done)
                        ? null
                        : () => _toggleAll(_selectedCount < _repos.length),
                    icon: Icon(
                      _selectedCount == _repos.length
                          ? Icons.deselect
                          : Icons.select_all,
                      size: AppIconSize.md,
                    ),
                    label: Text(
                      _selectedCount == _repos.length
                          ? context.l10n.gitDeselectAll
                          : context.l10n.gitSelectAll,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.gitStagedFiles(_selectedCount),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Repo list
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: AppDialog.listHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _repos.length,
                  itemBuilder: (ctx, i) {
                    final repo = _repos[i];
                    return CheckboxListTile(
                      dense: true,
                      value: repo.selected,
                      onChanged: (_running || _done)
                          ? null
                          : (v) => setState(() => repo.selected = v ?? false),
                      title: Text(repo.name),
                      subtitle: Text(
                        '${repo.changedFiles} file(s)',
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Commit message
              TextField(
                controller: _messageController,
                enabled: !_running && !_done,
                decoration: InputDecoration(
                  labelText: context.l10n.gitCommitMessage,
                  hintText: context.l10n.gitCommitMessageHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 8,
                minLines: 3,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Push after commit checkbox
              GestureDetector(
                onTap: (_running || _done)
                    ? null
                    : () => setState(() => _pushAfterCommit = !_pushAfterCommit),
                child: Row(
                  children: [
                    Checkbox(
                      value: _pushAfterCommit,
                      onChanged: (_running || _done)
                          ? null
                          : (v) => setState(() => _pushAfterCommit = v ?? false),
                    ),
                    Text(context.l10n.gitPushAfterCommit),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_running)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            // Log output
            Container(
              height: AppDialog.logHeightLg,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppLogColors.terminalBg,
                borderRadius: AppRadius.mediumBorderRadius,
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: _logLines.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.noOutputYet,
                        style: const TextStyle(
                            color: Colors.grey, fontFamily: 'monospace'),
                      ),
                    )
                  : SelectionArea(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in _logLines)
                                Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: AppFontSize.md,
                                    ),
                                    children: AnsiParser.parse(line),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
          ),
        ),
        ),
      ),
      actions: [
        if (_repos.isNotEmpty && !_running && !_done)
          FilledButton(
            onPressed: _canCommit ? _commit : null,
            child: Text(
              _pushAfterCommit
                  ? context.l10n.gitCommitAndPush
                  : context.l10n.gitCommitOnly,
            ),
        ),
      ],
    );
  }
}
