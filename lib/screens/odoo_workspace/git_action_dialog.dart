import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'repo_info.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

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
    if (mounted) context.setDialogRunning(true);
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
    if (mounted) {
      setState(() => _running = false);
      context.setDialogRunning(false);
    }
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
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
          ],
          ),
        ),
        ),
      ),
    );
  }
}
