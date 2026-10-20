import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/git_process.dart';
import 'package:odoo_auto_config/services/git_pull_rebase_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';
import 'package:odoo_auto_config/widgets/pull_rebase_log.dart';

/// Runs `git pull` sequentially in each repo and streams the log.
class SelectivePullLogDialog extends StatefulWidget {
  final String title;
  final List<({String name, String path})> repos;

  const SelectivePullLogDialog({
    super.key,
    required this.title,
    required this.repos,
  });

  @override
  State<SelectivePullLogDialog> createState() =>
      _SelectivePullLogDialogState();
}

class _SelectivePullLogDialogState extends State<SelectivePullLogDialog> {
  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  bool _running = false;

  /// Repos whose pull failed because the branch diverged from the remote; they
  /// get one "Pull (rebase) (N)" button once the batch is done.
  final List<({String name, String path})> _rebaseCandidates = [];

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

  Future<void> _run() async {
    setState(() => _running = true);
    if (mounted) context.setDialogRunning(true);
    for (final (name: repo, path: repoPath) in widget.repos) {
      _addLine('\x1B[0;34m> git pull ($repo)\x1B[0m');
      try {
        final process = await startGit(['pull'], workingDir: repoPath);
        final stdout = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) { if (mounted) _addLine(line); });
        final stderr = process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) { if (mounted) _addLine(line); });
        await process.exitCode;
        await stdout.cancel();
        await stderr.cancel();
        final exitCode = await process.exitCode;
        if (!mounted) return;
        if (exitCode == 0) {
          _addLine('\x1B[0;32m[+] $repo done\x1B[0m');
        } else {
          _addLine('\x1B[0;31m[-] $repo failed (exit $exitCode)\x1B[0m');
          final canRebase =
              await GitPullRebaseService.canOfferPullRebase(repoPath);
          if (!mounted) return;
          if (canRebase) {
            _addLine(
              '\x1B[0;33m[!] $repo: ${context.l10n.gitDivergedHint}\x1B[0m',
            );
            _rebaseCandidates.add((name: repo, path: repoPath));
          }
        }
      } catch (e) {
        if (mounted) _addLine('\x1B[0;31m[-] $repo: $e\x1B[0m');
      }
    }
    if (mounted) {
      _addLine('\x1B[0;32m[+] Done!\x1B[0m');
      setState(() => _running = false);
      context.setDialogRunning(false);
    }
  }

  /// Pull --rebase every repo collected in [_rebaseCandidates].
  Future<void> _pullRebaseCandidates() async {
    final repos = List.of(_rebaseCandidates);
    setState(() {
      _rebaseCandidates.clear();
      _running = true;
    });
    context.setDialogRunning(true);
    for (final (name: repo, path: repoPath) in repos) {
      if (!mounted) return;
      _addLine('\x1B[0;34m> git pull --rebase --autostash ($repo)\x1B[0m');
      try {
        final result = await GitPullRebaseService.pullRebase(
          repoPath,
          onOutput: (line) {
            if (mounted) _addLine(line);
          },
        );
        if (!mounted) return;
        _addLine(pullRebaseResultLine(context.l10n, result, repo: repo));
      } catch (e) {
        if (mounted) _addLine('\x1B[0;31m[-] $repo: $e\x1B[0m');
      }
    }
    if (mounted) {
      setState(() => _running = false);
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
            children: [
              if (_running)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
              LogOutput(
                lines: _logLines,
                height: AppDialog.logHeightXl,
                ansiColors: true,
                scrollController: _scrollController,
              ),
              if (!_running && _rebaseCandidates.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: _pullRebaseCandidates,
                      icon: const Icon(Icons.call_merge),
                      label: Text(
                        '${context.l10n.gitPullRebase}'
                        ' (${_rebaseCandidates.length})',
                      ),
                    ),
                  ),
                ),
          ],
          ),
        ),
        ),
      ),
    );
  }
}
