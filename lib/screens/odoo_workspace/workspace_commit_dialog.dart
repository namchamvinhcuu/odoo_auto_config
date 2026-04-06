import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import 'repo_info.dart';

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
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    30: Color(0xFF000000),
    31: Color(0xFFCD3131),
    32: Color(0xFF0DBC79),
    33: Color(0xFFE5E510),
    34: Color(0xFF2472C8),
    35: Color(0xFFBC3FBC),
    36: Color(0xFF11A8CD),
    37: Color(0xFFE5E5E5),
    90: Color(0xFF666666),
    91: Color(0xFFF14C4C),
    92: Color(0xFF23D18B),
    93: Color(0xFFF5F543),
    94: Color(0xFF3B8EEA),
    95: Color(0xFFD670D6),
    96: Color(0xFF29B8DB),
    97: Color(0xFFFFFFFF),
  };

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _logLines = [];
  bool _running = false;
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
    if (mounted) setState(() => _running = false);
  }

  List<TextSpan> _parseAnsi(String line) {
    final spans = <TextSpan>[];
    final defaultColor = Colors.grey.shade300;
    var currentColor = defaultColor;
    var lastEnd = 0;

    for (final match in _ansiRegex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: line.substring(lastEnd, match.start),
          style: TextStyle(color: currentColor),
        ));
      }
      final code = match.group(0)!;
      final params = code.substring(2, code.length - 1).split(';');
      for (final param in params) {
        final n = int.tryParse(param) ?? 0;
        if (n == 0) {
          currentColor = defaultColor;
        } else if (_ansiColors.containsKey(n)) {
          currentColor = _ansiColors[n]!;
        }
      }
      lastEnd = match.end;
    }
    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: TextStyle(color: currentColor),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final canCommit =
        !_running && _messageController.text.trim().isNotEmpty;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Repo list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
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
            ),
            const SizedBox(height: AppSpacing.sm),
            // Push after commit
            GestureDetector(
              onTap: () =>
                  setState(() => _pushAfterCommit = !_pushAfterCommit),
              child: Row(
                children: [
                  Checkbox(
                    value: _pushAfterCommit,
                    onChanged: (v) =>
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
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppLogColors.terminalBg,
                  borderRadius: AppRadius.mediumBorderRadius,
                  border: Border.all(color: Colors.grey.shade700),
                ),
                child: SelectionArea(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in _logLines)
                            Text.rich(
                              TextSpan(children: _parseAnsi(line)),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: AppFontSize.sm,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
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
