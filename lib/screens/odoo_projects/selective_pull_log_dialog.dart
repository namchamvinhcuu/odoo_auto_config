import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_running)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.sm),
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
                        style: const TextStyle(
                            color: Colors.grey, fontFamily: 'monospace'),
                      ),
                    )
                  : SelectionArea(
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
        ),
      ),
    );
  }
}
