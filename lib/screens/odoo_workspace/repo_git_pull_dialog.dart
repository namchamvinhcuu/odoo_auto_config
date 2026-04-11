import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

// ── Repo Git Pull Dialog ──

class RepoGitPullDialog extends StatefulWidget {
  final String repoName;
  final String repoPath;
  final String? targetBranch;
  final String? currentBranch;

  const RepoGitPullDialog({
    super.key,
    required this.repoName,
    required this.repoPath,
    this.targetBranch,
    this.currentBranch,
  });

  @override
  State<RepoGitPullDialog> createState() => _RepoGitPullDialogState();
}

class _RepoGitPullDialogState extends State<RepoGitPullDialog> {
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
        workingDirectory: widget.repoPath,
        runInShell: true,
      );

  Future<void> _runProcess(List<String> args) async {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: widget.repoPath,
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
      workingDirectory: widget.repoPath,
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

    final status = await _git(['status', '--porcelain']);
    final hasChanges = (status.stdout as String).trimRight().isNotEmpty;

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

    _addLine('\x1B[0;33m[~] Switching to $target...\x1B[0m');
    final checkout = await _git(['checkout', target]);
    if (checkout.exitCode != 0) {
      _addLine(
        '\x1B[0;31m[-] Checkout failed: ${(checkout.stderr as String).trim()}\x1B[0m',
      );
      if (hasChanges) await _git(['stash', 'pop']);
      return;
    }

    _addLine('\x1B[0;33m[~] Pulling $target...\x1B[0m');
    await _runProcess(['pull']);

    _addLine('\x1B[0;33m[~] Switching back to $current...\x1B[0m');
    await _git(['checkout', current]);

    if (hasChanges) {
      _addLine('\x1B[0;33m[~] Restoring stash...\x1B[0m');
      await _git(['stash', 'pop']);
    }

    if (mounted) {
      _addLine('\x1B[0;32m[+] Pulled $target successfully\x1B[0m');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.targetBranch != null
                  ? 'Pull ${widget.targetBranch} — ${widget.repoName}'
                  : context.l10n.gitPullTitle(widget.repoName),
            ),
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
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_running)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: LinearProgressIndicator(),
                ),
              LogOutput(
                lines: _logLines,
                height: AppDialog.logHeightLg,
                ansiColors: true,
                scrollController: _scrollController,
              ),
          ],
          ),
        ),
        ),
      ),
    );
  }
}
