import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/screens/home_screen.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'repo_commit_dialog.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

// ── Repo Create PR Dialog ──

class RepoCreatePRDialog extends StatefulWidget {
  final String repoName;
  final String repoPath;
  final String currentBranch;

  const RepoCreatePRDialog({
    super.key,
    required this.repoName,
    required this.repoPath,
    required this.currentBranch,
  });

  @override
  State<RepoCreatePRDialog> createState() => _RepoCreatePRDialogState();
}

class _RepoCreatePRDialogState extends State<RepoCreatePRDialog> {
  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _running = false;
  bool _done = false;
  bool _loading = true;
  bool _ghInstalled = false;
  bool _ghAuthed = false;
  bool _ghNativeAuth = false;
  bool _noChanges = false;
  String? _token;
  String _baseBranch = 'main';
  List<String> _remoteBranches = [];
  String? _prUrl;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.currentBranch;
    _checkGh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// Read GitHub token from project's git-repositories script.
  Future<String?> _readProjectToken(String projectPath) async {
    final shPath = p.join(projectPath, 'git-repositories.sh');
    final ps1Path = p.join(projectPath, 'git-repositories.ps1');
    String? scriptPath;
    if (await File(ps1Path).exists()) {
      scriptPath = ps1Path;
    } else if (await File(shPath).exists()) {
      scriptPath = shPath;
    }
    if (scriptPath == null) return null;
    final content = await File(scriptPath).readAsString();
    final match = RegExp(r'TOKEN\s*=\s*"([^"]*)"').firstMatch(content);
    final token = match?.group(1) ?? '';
    return token.isEmpty ? null : token;
  }

  Future<void> _checkGh() async {
    final result = await PlatformService.runGh(['--version']);
    final installed = result.exitCode == 0;

    // Read token from project's git-repositories script (project-specific account)
    // repoPath is projectPath/addons/repoName/ → project root is 2 levels up
    final projectPath = p.dirname(p.dirname(widget.repoPath));
    String? token = await _readProjectToken(projectPath);
    // Fall back to default git account token
    token ??= await StorageService.getDefaultGitToken();

    // Check if gh is already authenticated via `gh auth login`
    bool ghNativeAuth = false;
    if (installed) {
      final authResult = await PlatformService.runGh(['auth', 'status']);
      ghNativeAuth = authResult.exitCode == 0;
    }
    // Authed = either gh auth login or app token
    final authed = ghNativeAuth || token != null;

    List<String> branches = [];
    final brResult = await Process.run(
      'git',
      ['branch', '-r', '--format=%(refname:short)'],
      workingDirectory: widget.repoPath,
      runInShell: true,
    );
    if (brResult.exitCode == 0) {
      branches = (brResult.stdout as String)
          .split('\n')
          .map((b) => b.trim())
          .where((b) => b.startsWith('origin/') && !b.contains('HEAD'))
          .map((b) => b.replaceFirst('origin/', ''))
          .where((b) => b != widget.currentBranch)
          .toSet()
          .toList()
        ..sort();
    }

    String base = 'main';
    if (branches.contains('main')) {
      base = 'main';
    } else if (branches.contains('master')) {
      base = 'master';
    } else if (branches.contains('dev')) {
      base = 'dev';
    }

    final noChanges = await _checkDiffFor(base);

    if (mounted) {
      setState(() {
        _ghInstalled = installed;
        _ghAuthed = authed;
        _ghNativeAuth = ghNativeAuth;
        _token = token;
        _remoteBranches = branches;
        _baseBranch = base;
        _noChanges = noChanges;
        _loading = false;
      });
    }
  }

  Future<bool> _checkDiffFor(String base) async {
    await Process.run(
      'git',
      ['fetch', 'origin', base, '--quiet'],
      workingDirectory: widget.repoPath,
      runInShell: true,
    );
    if (!mounted) return false;
    final result = await Process.run(
      'git',
      ['rev-list', '--count', 'origin/$base..HEAD'],
      workingDirectory: widget.repoPath,
      runInShell: true,
    );
    final count = int.tryParse((result.stdout as String).trim()) ?? 0;
    return count == 0;
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

  Future<void> _createPR() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _running = true);
    context.setDialogRunning(true);

    // Check uncommitted changes
    final status = await Process.run(
      'git',
      ['status', '--porcelain'],
      workingDirectory: widget.repoPath,
      runInShell: true,
    );
    final uncommitted = (status.stdout as String)
        .trimRight()
        .split('\n')
        .where((l) => l.isNotEmpty)
        .length;

    if (uncommitted > 0 && mounted) {
      setState(() => _running = false);
      context.setDialogRunning(false);
      final proceed = await AppDialog.show<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Text(context.l10n.prUncommittedTitle),
              const Spacer(),
              AppDialog.closeButton(ctx),
            ],
          ),
          content: Text(ctx.l10n.prUncommittedDesc(uncommitted)),
          actions: [
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(ctx, false);
                // Close PR dialog, then open commit dialog
                Navigator.pop(context);
                AppDialog.show(
                  context: context,
                  builder: (c) => RepoCommitDialog(
                    repoName: widget.repoName,
                    repoPath: widget.repoPath,
                  ),
                );
              },
              icon: const Icon(Icons.commit),
              label: Text(ctx.l10n.prCommitFirst),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.prContinueAnyway),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
      setState(() => _running = true);
      context.setDialogRunning(true);
    }

    // Push first
    _addLine(
        '\x1B[0;33m[~] Pushing ${widget.currentBranch} to origin...\x1B[0m');
    final push = await Process.start(
      'git',
      ['push', '-u', 'origin', widget.currentBranch],
      workingDirectory: widget.repoPath,
      runInShell: true,
    );
    push.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (mounted) _addLine(line);
    });
    push.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (mounted) _addLine(line);
    });
    final pushExit = await push.exitCode;
    if (pushExit != 0) {
      if (mounted) {
        _addLine('\x1B[0;31m[-] Push failed\x1B[0m');
        setState(() => _running = false);
        context.setDialogRunning(false);
      }
      return;
    }

    // Create PR
    _addLine('\x1B[0;33m[~] Creating pull request...\x1B[0m');
    final args = [
      'pr',
      'create',
      '--base',
      _baseBranch,
      '--title',
      title,
    ];
    final body = _bodyController.text.trim().isNotEmpty
        ? _bodyController.text.trim()
        : 'Merge `${widget.currentBranch}` into `$_baseBranch`';
    args.addAll(['--body', body]);

    final pr = await PlatformService.startGh(
      args,
      workingDirectory: widget.repoPath,
      // Only pass GH_TOKEN as fallback when gh is not natively authenticated
      // This respects gh auth login / gh auth switch for multi-account users
      environment: (!_ghNativeAuth && _token != null)
          ? {'GH_TOKEN': _token!}
          : null,
    );
    pr.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (mounted) {
        _addLine(line);
        if (line.startsWith('http')) {
          setState(() => _prUrl = line.trim());
        }
      }
    });
    pr.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (mounted) {
        _addLine(line);
        final urlMatch = RegExp(r'https://\S+').firstMatch(line);
        if (urlMatch != null) {
          setState(() => _prUrl = urlMatch.group(0));
        }
      }
    });
    final prExit = await pr.exitCode;

    if (!mounted) return;
    if (prExit == 0) {
      _addLine('\x1B[0;32m[+] Pull request created!\x1B[0m');
      setState(() {
        _done = true;
        _running = false;
      });
      context.setDialogRunning(false);
    } else if (_prUrl != null) {
      _addLine(
        '\x1B[0;33m[~] PR already exists. New commits have been pushed.\x1B[0m',
      );
      setState(() {
        _done = true;
        _running = false;
      });
      context.setDialogRunning(false);
    } else {
      _addLine('\x1B[0;31m[-] Failed to create pull request\x1B[0m');
      setState(() => _running = false);
      context.setDialogRunning(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.prTitle(widget.repoName)),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (!_ghInstalled)
              Column(
                children: [
                  const Icon(Icons.warning_amber,
                      color: Colors.orange, size: AppIconSize.xxxl),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.l10n.prGhNotInstalled,
                    style: const TextStyle(fontSize: AppFontSize.xl),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.prGhInstallHint,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.md,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              )
            else if (!_ghAuthed)
              Column(
                children: [
                  const Icon(Icons.key_off,
                      color: Colors.orange, size: AppIconSize.xxxl),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.l10n.prGhNoToken,
                    style: const TextStyle(fontSize: AppFontSize.xl),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.prGhNoTokenDesc,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(context);
                      HomeScreen.navigateToSettings(settingsTab: 5);
                    },
                    icon: const Icon(Icons.settings),
                    label: Text(context.l10n.prGhGoToGitSettings),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Text(context.l10n.prBase,
                      style: TextStyle(color: Colors.grey.shade400)),
                  const SizedBox(width: AppSpacing.sm),
                  DropdownButton<String>(
                    value: _remoteBranches.contains(_baseBranch)
                        ? _baseBranch
                        : _remoteBranches.firstOrNull,
                    isDense: true,
                    items: _remoteBranches
                        .map((b) => DropdownMenuItem(
                              value: b,
                              child: Text(b),
                            ))
                        .toList(),
                    onChanged: (_running || _done)
                        ? null
                        : (v) async {
                            if (v != null) {
                              setState(() => _baseBranch = v);
                              final noChanges = await _checkDiffFor(v);
                              if (mounted) {
                                setState(() => _noChanges = noChanges);
                              }
                            }
                          },
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(Icons.arrow_back,
                      size: AppIconSize.md,
                      color: Colors.grey.shade500),
                  const SizedBox(width: AppSpacing.sm),
                  Chip(
                    label: Text(widget.currentBranch,
                        style:
                            const TextStyle(fontFamily: 'monospace')),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (_noChanges && !_done) ...[
                const SizedBox(height: AppSpacing.lg),
                Icon(Icons.merge_type,
                    size: AppIconSize.xxxl, color: Colors.grey.shade500),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.prNoChanges,
                  style: TextStyle(
                    fontSize: AppFontSize.xl,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.prNoChangesDesc(
                      _baseBranch, widget.currentBranch),
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (!_noChanges || _done) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: context.l10n.prTitleLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_running && !_done,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _bodyController,
                  decoration: InputDecoration(
                    labelText: context.l10n.prDescriptionLabel,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  minLines: 2,
                  maxLines: 5,
                  enabled: !_running && !_done,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: (_running ||
                              _done ||
                              _titleController.text.trim().isEmpty)
                          ? null
                          : _createPR,
                      icon: _running
                          ? const SizedBox(
                              width: AppIconSize.md,
                              height: AppIconSize.md,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send),
                      label: Text(context.l10n.prCreateButton),
                    ),
                    if (_done) ...[
                      const SizedBox(width: AppSpacing.md),
                      const Icon(Icons.check_circle,
                          color: Colors.green),
                      const SizedBox(width: AppSpacing.xs),
                      Text(context.l10n.prCreated,
                          style:
                              const TextStyle(color: Colors.green)),
                      if (_prUrl != null) ...[
                        const SizedBox(width: AppSpacing.md),
                        FilledButton.tonalIcon(
                          onPressed: () => Process.run(
                            Platform.isMacOS
                                ? 'open'
                                : Platform.isWindows
                                    ? 'start'
                                    : 'xdg-open',
                            [_prUrl!],
                            runInShell: true,
                          ),
                          icon: const Icon(Icons.open_in_new,
                              size: AppIconSize.md),
                          label: Text(context.l10n.prViewInBrowser),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ],
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              LogOutput(
                lines: _logLines,
                height: AppDialog.logHeightSm,
                ansiColors: true,
                scrollController: _scrollController,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
