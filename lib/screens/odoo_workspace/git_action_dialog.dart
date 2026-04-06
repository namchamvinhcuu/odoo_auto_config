import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import 'repo_info.dart';

// ── Git Action Dialog (Pull / Push / Switch Branch) ──

class GitActionDialog extends StatefulWidget {
  final String title;
  final List<RepoInfo> repos;

  /// 'pull', 'push', 'switch', or 'publish'
  final String action;
  final String? branch;
  final VoidCallback onDone;

  const GitActionDialog({
    super.key,
    required this.title,
    required this.repos,
    required this.action,
    this.branch,
    required this.onDone,
  });

  @override
  State<GitActionDialog> createState() => _GitActionDialogState();
}

class _GitActionDialogState extends State<GitActionDialog> {
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
      switch (widget.action) {
        case 'pull':
          await _pullRepo(repo);
        case 'push':
          await _pushRepo(repo);
        case 'switch':
          await _switchRepo(repo, widget.branch!);
        case 'publish':
          await _publishRepo(repo);
      }
    }
    widget.onDone();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _pullRepo(RepoInfo repo) async {
    _addLine('\x1B[0;34m[*] Pulling ${repo.name}...\x1B[0m');
    final process = await Process.start(
      'git', ['pull'],
      workingDirectory: repo.path, runInShell: true,
    );
    await _listenProcess(process);
    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${repo.name}: done\x1B[0m');
    } else {
      _addLine('\x1B[0;31m[-] ${repo.name}: failed (exit $exitCode)\x1B[0m');
    }
  }

  Future<void> _pushRepo(RepoInfo repo) async {
    _addLine('\x1B[0;36m[>] Pushing ${repo.name}...\x1B[0m');
    final process = await Process.start(
      'git', ['push'],
      workingDirectory: repo.path, runInShell: true,
    );
    await _listenProcess(process);
    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${repo.name}: pushed\x1B[0m');
    } else {
      _addLine('\x1B[0;31m[-] ${repo.name}: push failed\x1B[0m');
    }
  }

  Future<void> _publishRepo(RepoInfo repo) async {
    _addLine(
        '\x1B[0;36m[>] Publishing ${repo.name} (${repo.branch})...\x1B[0m');
    final process = await Process.start(
      'git',
      ['push', '-u', 'origin', repo.branch],
      workingDirectory: repo.path,
      runInShell: true,
    );
    await _listenProcess(process);
    final exitCode = await process.exitCode;
    if (exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${repo.name}: published\x1B[0m');
    } else {
      _addLine('\x1B[0;31m[-] ${repo.name}: publish failed\x1B[0m');
    }
  }

  Future<void> _switchRepo(RepoInfo repo, String branch) async {
    _addLine('\x1B[0;34m[*] Switching ${repo.name} to $branch...\x1B[0m');
    var result = await Process.run(
      'git', ['checkout', branch],
      workingDirectory: repo.path, runInShell: true,
    );
    if (result.exitCode != 0) {
      result = await Process.run(
        'git', ['checkout', '-b', branch, 'origin/$branch'],
        workingDirectory: repo.path, runInShell: true,
      );
    }
    if (result.exitCode != 0) {
      result = await Process.run(
        'git', ['checkout', '-b', branch],
        workingDirectory: repo.path, runInShell: true,
      );
    }
    if (result.exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${repo.name}: switched to $branch\x1B[0m');
    } else {
      final err = (result.stderr as String).trim();
      _addLine('\x1B[0;31m[-] ${repo.name}: failed — $err\x1B[0m');
    }
  }

  Future<void> _listenProcess(Process process) async {
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
          Expanded(child: Text(widget.title)),
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
