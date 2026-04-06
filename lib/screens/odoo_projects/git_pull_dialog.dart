import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';

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
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    30: Color(0xFF000000), // black
    31: Color(0xFFCD3131), // red
    32: Color(0xFF0DBC79), // green
    33: Color(0xFFE5E510), // yellow
    34: Color(0xFF2472C8), // blue
    35: Color(0xFFBC3FBC), // magenta
    36: Color(0xFF11A8CD), // cyan
    37: Color(0xFFE5E5E5), // white
    90: Color(0xFF666666), // bright black (gray)
    91: Color(0xFFF14C4C), // bright red
    92: Color(0xFF23D18B), // bright green
    93: Color(0xFFF5F543), // bright yellow
    94: Color(0xFF3B8EEA), // bright blue
    95: Color(0xFFD670D6), // bright magenta
    96: Color(0xFF29B8DB), // bright cyan
    97: Color(0xFFFFFFFF), // bright white
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
      for (final p in params) {
        final n = int.tryParse(p) ?? 0;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_running)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            Container(
              height: 350,
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
                        style: const TextStyle(color: Colors.grey, fontFamily: 'monospace'),
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
