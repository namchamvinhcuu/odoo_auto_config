import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class GitPullDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;
  final String scriptPath;

  const GitPullDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
    required this.scriptPath,
  });

  @override
  State<GitPullDialog> createState() => _GitPullDialogState();
}

class _GitPullDialogState extends State<GitPullDialog> {
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
    try {
      final String executable;
      final List<String> args;
      if (Platform.isWindows) {
        executable = 'powershell';
        args = ['-ExecutionPolicy', 'Bypass', '-File', widget.scriptPath];
      } else {
        executable = 'bash';
        args = [widget.scriptPath];
      }
      final process = await Process.start(
        executable,
        args,
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (mounted) _addLine(line);
      });
      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (mounted) _addLine(line);
      });
      final exitCode = await process.exitCode;
      if (!mounted) return;
      if (exitCode == 0) {
        _addLine('\x1B[0;32m[+] ${context.l10n.gitPullDone}\x1B[0m');
      } else {
        _addLine('\x1B[0;31m[-] ${context.l10n.gitPullFailed(exitCode)}\x1B[0m');
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitPullTitle(widget.projectName)),
          const Spacer(),
          AppDialog.closeButton(context, enabled: !_running),
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
