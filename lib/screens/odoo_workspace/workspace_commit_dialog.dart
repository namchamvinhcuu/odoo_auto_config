import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'repo_info.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

// ── Workspace Commit Dialog ──

class WorkspaceCommitDialog extends StatefulWidget {
  final List<RepoInfo> repos;
  final VoidCallback onDone;

  const WorkspaceCommitDialog({
    super.key,
    required this.repos,
    required this.onDone,
  });

  @override
  State<WorkspaceCommitDialog> createState() =>
      _WorkspaceCommitDialogState();
}

class _WorkspaceCommitDialogState extends State<WorkspaceCommitDialog> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _logLines = [];
  bool _running = false;
  bool _done = false;
  bool _pushAfterCommit = true;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _running = true);
    for (final repo in widget.repos) {
      _addLine('\x1B[0;34m[*] Committing ${repo.name}...\x1B[0m');

      // git add -A
      final addResult = await Process.run(
        'git',
        ['add', '-A'],
        workingDirectory: repo.path,
        runInShell: true,
      );
      if (addResult.exitCode != 0) {
        _addLine(
            '\x1B[0;31m[-] git add failed: ${addResult.stderr}\x1B[0m');
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
        if (pushExit != 0) {
          _addLine(
              '\x1B[0;31m[-] Push failed for ${repo.name}\x1B[0m');
        }
      }

      _addLine('\x1B[0;32m[+] ${repo.name}: committed\x1B[0m');
    }
    widget.onDone();
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCommit =
        !_running && !_done && _messageController.text.trim().isNotEmpty;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(context.l10n.gitCommitTitle(
                '${widget.repos.length} repos')),
          ),
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
            children: [
              // Repo list
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: AppDialog.listHeightSm),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.repos.length,
                    itemBuilder: (ctx, i) {
                      final repo = widget.repos[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder,
                            size: AppIconSize.md, color: Colors.orange),
                        title: Text(repo.name,
                            style: const TextStyle(fontSize: AppFontSize.md)),
                        trailing: Text(
                          '${repo.changedFiles} file(s)',
                          style: TextStyle(
                            fontSize: AppFontSize.sm,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Commit message
              TextField(
                controller: _messageController,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: context.l10n.gitCommitMessage,
                  hintText: context.l10n.gitCommitMessageHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                autofocus: true,
                enabled: !_running && !_done,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Push after commit
              GestureDetector(
                onTap: (_running || _done)
                    ? null
                    : () =>
                        setState(() => _pushAfterCommit = !_pushAfterCommit),
                child: Row(
                  children: [
                    Checkbox(
                      value: _pushAfterCommit,
                      onChanged: (_running || _done)
                          ? null
                          : (v) =>
                              setState(() => _pushAfterCommit = v ?? true),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text(
                      context.l10n.gitPushAfterCommit,
                      style: const TextStyle(fontSize: AppFontSize.sm),
                    ),
                  ],
                ),
              ),
              // Log output
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: LogOutput(
                    lines: _logLines,
                    maxHeight: AppDialog.logHeightMd,
                    ansiColors: true,
                    scrollController: _scrollController,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: canCommit ? _commit : null,
          icon: const Icon(Icons.check, size: AppIconSize.md),
          label: Text(
            _pushAfterCommit
                ? context.l10n.workspaceViewCommitPush
                : context.l10n.workspaceViewCommitOnly,
          ),
        ),
      ],
    );
  }
}
