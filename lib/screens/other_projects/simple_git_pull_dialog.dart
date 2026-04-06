import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';

class SimpleGitPullDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;
  final String? targetBranch; // pull another branch without switching
  final String? currentBranch; // required when targetBranch is set

  const SimpleGitPullDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
    this.targetBranch,
    this.currentBranch,
  });

  @override
  State<SimpleGitPullDialog> createState() => _SimpleGitPullDialogState();
}

class _SimpleGitPullDialogState extends State<SimpleGitPullDialog> {
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    31: Color(0xFFCD3131),
    32: Color(0xFF0DBC79),
    33: Color(0xFFE5E510),
    34: Color(0xFF2472C8),
    90: Color(0xFF666666),
  };

  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
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

  Future<ProcessResult> _git(List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: widget.projectPath,
        runInShell: true,
      );

  Future<void> _runProcess(List<String> args) async {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (mounted) _addLine(line);
        });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (mounted) _addLine(line);
        });
    await process.exitCode;
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      if (widget.targetBranch != null) {
        await _runPullOtherBranch();
      } else {
        await _runPullCurrent();
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _runPullCurrent() async {
    final process = await Process.start(
      'git',
      ['pull'],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (mounted) _addLine(line);
        });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (mounted) _addLine(line);
        });
    final exitCode = await process.exitCode;
    if (!mounted) return;
    if (exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${context.l10n.gitPullDone}\x1B[0m');
    } else {
      _addLine(
        '\x1B[0;31m[-] ${context.l10n.gitPullFailed(exitCode)}\x1B[0m',
      );
    }
  }

  Future<void> _runPullOtherBranch() async {
    final target = widget.targetBranch!;
    final current = widget.currentBranch!;

    // Check for uncommitted changes
    final status = await _git(['status', '--porcelain']);
    final hasChanges = (status.stdout as String).trimRight().isNotEmpty;

    // Stash if needed
    if (hasChanges) {
      _addLine('\x1B[0;33m[~] Stashing changes...\x1B[0m');
      final stash =
          await _git(['stash', 'push', '-m', 'auto-stash for pull $target']);
      if (stash.exitCode != 0) {
        _addLine(
          '\x1B[0;31m[-] Stash failed: ${(stash.stderr as String).trim()}\x1B[0m',
        );
        return;
      }
    }

    // Checkout target
    _addLine('\x1B[0;33m[~] Switching to $target...\x1B[0m');
    final checkout = await _git(['checkout', target]);
    if (checkout.exitCode != 0) {
      _addLine(
        '\x1B[0;31m[-] Checkout failed: ${(checkout.stderr as String).trim()}\x1B[0m',
      );
      if (hasChanges) await _git(['stash', 'pop']);
      return;
    }

    // Pull
    _addLine('\x1B[0;33m[~] Pulling $target...\x1B[0m');
    await _runProcess(['pull']);

    // Switch back
    _addLine('\x1B[0;33m[~] Switching back to $current...\x1B[0m');
    await _git(['checkout', current]);

    // Restore stash
    if (hasChanges) {
      _addLine('\x1B[0;33m[~] Restoring stash...\x1B[0m');
      await _git(['stash', 'pop']);
    }

    if (mounted) {
      _addLine('\x1B[0;32m[+] Pulled $target successfully\x1B[0m');
    }
  }

  List<TextSpan> _parseAnsi(String line) {
    final spans = <TextSpan>[];
    final defaultColor = Colors.grey.shade300;
    var currentColor = defaultColor;
    var lastEnd = 0;

    for (final match in _ansiRegex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: line.substring(lastEnd, match.start),
            style: TextStyle(color: currentColor),
          ),
        );
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
      spans.add(
        TextSpan(
          text: line.substring(lastEnd),
          style: TextStyle(color: currentColor),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.targetBranch != null
                  ? 'Pull ${widget.targetBranch} — ${widget.projectName}'
                  : context.l10n.gitPullTitle(widget.projectName),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppDialog.closeButton(context, enabled: !_running),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_running)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            Container(
              height: 250,
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
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
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
                                    children: _parseAnsi(line),
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
    );
  }
}
