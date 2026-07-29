import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/git_process.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

/// Streams `git push` for one Other Project so unpushed commits can be shipped
/// straight from the project card, without opening the Git Branches dialog.
///
/// Mirrors [SimpleGitPullDialog]: same log-streaming shape and ANSI result line.
class SimpleGitPushDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  /// Set to publish a branch that has no upstream yet: runs
  /// `push -u origin <branch>` instead of a plain `push`, which would fail with
  /// "no upstream branch".
  ///
  /// Unlike [GitBranchService.publishBranch] this does NOT create an empty
  /// commit — that helper exists for a fresh branch with no commits of its own,
  /// and here the branch already has the work we want to publish.
  final String? publishBranch;

  const SimpleGitPushDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
    this.publishBranch,
  });

  @override
  State<SimpleGitPushDialog> createState() => _SimpleGitPushDialogState();
}

class _SimpleGitPushDialogState extends State<SimpleGitPushDialog> {
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
    // git writes progress with \r; keep only the final segment of the line.
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
    try {
      final branch = widget.publishBranch;
      final process = await startGit(
        branch == null ? ['push'] : ['push', '-u', 'origin', branch],
        workingDir: widget.projectPath,
      );
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      // git push reports progress AND rejection reasons on stderr — surface it
      // instead of leaving a silent failure.
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      final exitCode = await process.exitCode;
      if (mounted) {
        if (exitCode == 0) {
          _addLine('\x1B[0;32m[+] ${context.l10n.gitPushDone}\x1B[0m');
        } else {
          _addLine(
            '\x1B[0;31m[-] ${context.l10n.gitPushFailed(exitCode)}\x1B[0m',
          );
        }
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
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
          Expanded(child: Text(context.l10n.gitPushTitle(widget.projectName))),
          const SizedBox(width: AppSpacing.sm),
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
