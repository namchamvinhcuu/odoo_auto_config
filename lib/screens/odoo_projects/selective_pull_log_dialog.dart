import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class SelectivePullLogDialog extends StatefulWidget {
  final String projectPath;
  final List<String> repos;

  const SelectivePullLogDialog({
    super.key,
    required this.projectPath,
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
    for (final repo in widget.repos) {
      final repoPath = p.join(widget.projectPath, 'addons', repo);
      _addLine('\x1B[0;34m> git pull ($repo)\x1B[0m');
      try {
        final process = await Process.start(
          'git', ['pull'],
          workingDirectory: repoPath,
          runInShell: true,
        );
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
        }
      } catch (e) {
        if (mounted) _addLine('\x1B[0;31m[-] $repo: $e\x1B[0m');
      }
    }
    if (mounted) {
      _addLine('\x1B[0;32m[+] Done!\x1B[0m');
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitSelectivePullTitle(
              '${widget.repos.length} repos')),
          const Spacer(),
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
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
              LogOutput(
                lines: _logLines,
                height: AppDialog.logHeightXl,
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
