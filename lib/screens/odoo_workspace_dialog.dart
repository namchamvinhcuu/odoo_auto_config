import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../services/storage_service.dart';

/// Data class for a single repo inside addons/
class _RepoInfo {
  final String name;
  final String path;
  String branch = '';
  int changedFiles = 0;
  int aheadCount = 0;
  int behindCount = 0;
  bool selected = false;

  _RepoInfo({
    required this.name,
    required this.path,
  });
}

/// Odoo Workspace View — dashboard for managing pinned repos in addons/
class OdooWorkspaceDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const OdooWorkspaceDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<OdooWorkspaceDialog> createState() => _OdooWorkspaceDialogState();
}

class _OdooWorkspaceDialogState extends State<OdooWorkspaceDialog> {
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

  /// All repo names found in addons/ (for search/add)
  List<String> _allRepoNames = [];

  /// Pinned repos (persisted, shown in main list)
  final List<_RepoInfo> _repos = [];

  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  final _addRepoController = TextEditingController();
  final _addRepoFocusNode = FocusNode();
  bool _scanning = true;
  bool _running = false;

  String get _storageKey => 'workspaceRepos_${widget.projectPath}';
  String get _selectionKey => 'workspaceSelected_${widget.projectPath}';

  @override
  void initState() {
    super.initState();
    _loadPinnedRepos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _addRepoController.dispose();
    _addRepoFocusNode.dispose();
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

  // ── Data loading ──

  Future<void> _loadPinnedRepos() async {
    setState(() {
      _scanning = true;
      _repos.clear();
    });

    try {
      // Scan all repos in addons/
      final addonsDir = Directory(p.join(widget.projectPath, 'addons'));
      final allNames = <String>[];
      if (await addonsDir.exists()) {
        await for (final entity in addonsDir.list()) {
          if (entity is Directory) {
            final gitDir = Directory(p.join(entity.path, '.git'));
            if (await gitDir.exists()) {
              allNames.add(p.basename(entity.path));
            }
          }
        }
      }
      allNames.sort();
      _allRepoNames = allNames;

      // Load persisted pinned list
      final settings = await StorageService.loadSettings();
      final saved = (settings[_storageKey] as List?)
              ?.map((e) => e.toString())
              .where((r) => allNames.contains(r))
              .toList() ??
          [];

      // Load persisted selection
      final selectedSet = (settings[_selectionKey] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{};

      // Build _repos from pinned names
      for (final name in saved) {
        final repo = _RepoInfo(
          name: name,
          path: p.join(widget.projectPath, 'addons', name),
        );
        repo.selected = selectedSet.contains(name);
        _repos.add(repo);
      }

      if (mounted) setState(() {});

      // Load statuses in parallel
      if (_repos.isNotEmpty) {
        await Future.wait(_repos.map(_loadRepoStatus));
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _loadRepoStatus(_RepoInfo repo) async {
    // Branch
    final branchResult = await Process.run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: repo.path,
      runInShell: true,
    );
    if (branchResult.exitCode == 0) {
      repo.branch = (branchResult.stdout as String).trim();
    }

    // Changed files
    final statusResult = await Process.run(
      'git',
      ['status', '--porcelain'],
      workingDirectory: repo.path,
      runInShell: true,
    );
    if (statusResult.exitCode == 0) {
      final output = (statusResult.stdout as String).trimRight();
      repo.changedFiles =
          output.isEmpty ? 0 : LineSplitter.split(output).length;
    }

    // Fetch quietly for ahead/behind
    await Process.run(
      'git',
      ['fetch', '--quiet'],
      workingDirectory: repo.path,
      runInShell: true,
    );

    // Ahead
    final aheadResult = await Process.run(
      'git',
      ['rev-list', '--count', '@{upstream}..HEAD'],
      workingDirectory: repo.path,
      runInShell: true,
    );
    if (aheadResult.exitCode == 0) {
      repo.aheadCount =
          int.tryParse((aheadResult.stdout as String).trim()) ?? 0;
    }

    // Behind
    final behindResult = await Process.run(
      'git',
      ['rev-list', '--count', 'HEAD..@{upstream}'],
      workingDirectory: repo.path,
      runInShell: true,
    );
    if (behindResult.exitCode == 0) {
      repo.behindCount =
          int.tryParse((behindResult.stdout as String).trim()) ?? 0;
    }

    if (mounted) setState(() {});
  }

  // ── Pin / Unpin ──

  Future<void> _savePinnedList() async {
    final settings = await StorageService.loadSettings();
    settings[_storageKey] = _repos.map((r) => r.name).toList();
    settings[_selectionKey] =
        _repos.where((r) => r.selected).map((r) => r.name).toList();
    await StorageService.saveSettings(settings);
  }

  Future<void> _saveSelection() async {
    final settings = await StorageService.loadSettings();
    settings[_selectionKey] =
        _repos.where((r) => r.selected).map((r) => r.name).toList();
    await StorageService.saveSettings(settings);
  }

  Future<void> _addRepo(String name) async {
    if (_repos.any((r) => r.name == name)) return;
    final repo = _RepoInfo(
      name: name,
      path: p.join(widget.projectPath, 'addons', name),
    );
    setState(() {
      _repos.add(repo);
      _repos.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });
    await _savePinnedList();
    await _loadRepoStatus(repo);
  }

  Future<void> _removeRepo(_RepoInfo repo) async {
    setState(() => _repos.remove(repo));
    await _savePinnedList();
  }

  // ── Helpers ──

  /// Repo names available to add (not yet pinned)
  List<String> get _availableToAdd {
    final pinnedNames = _repos.map((r) => r.name).toSet();
    return _allRepoNames.where((n) => !pinnedNames.contains(n)).toList();
  }

  int get _selectedCount => _repos.where((r) => r.selected).length;

  Color _branchColor(String branch) {
    final b = branch.toLowerCase();
    if (b == 'main' || b == 'master') return Colors.green;
    if (b == 'dev' || b == 'develop' || b.startsWith('dev')) {
      return Colors.orange;
    }
    if (b.startsWith('feature') || b.startsWith('feat')) return Colors.blue;
    if (b.startsWith('hotfix') || b.startsWith('fix')) return Colors.red;
    return Colors.cyan;
  }

  void _toggleAll(bool select) {
    setState(() {
      for (final r in _repos) {
        r.selected = select;
      }
    });
    _saveSelection();
  }

  // ── Batch actions ──

  Future<void> _pullSelected() async {
    final selected = _repos.where((r) => r.selected).toList();
    if (selected.isEmpty) return;
    setState(() => _running = true);
    for (final repo in selected) {
      _addLine('\x1B[0;34m[*] Pulling ${repo.name}...\x1B[0m');
      final process = await Process.start(
        'git',
        ['pull'],
        workingDirectory: repo.path,
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
      if (exitCode == 0) {
        _addLine('\x1B[0;32m[+] ${repo.name}: done\x1B[0m');
      } else {
        _addLine(
            '\x1B[0;31m[-] ${repo.name}: failed (exit $exitCode)\x1B[0m');
      }
      await _loadRepoStatus(repo);
    }
    if (mounted) setState(() => _running = false);
  }

  void _openCommitDialog() {
    final reposWithChanges = _repos
        .where((r) => r.selected && r.changedFiles > 0)
        .toList();

    if (reposWithChanges.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.grey,
              size: AppIconSize.xxl),
          content: Text(
            context.l10n.gitCommitNoChanges,
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.close),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _WorkspaceCommitDialog(
        repos: reposWithChanges,
        onDone: () {
          // Refresh status sau khi commit
          for (final repo in reposWithChanges) {
            _loadRepoStatus(repo);
          }
        },
      ),
    );
  }

  Future<void> _switchBranchAll() async {
    final controller = TextEditingController();
    // Collect all unique branches across pinned repos
    final allBranches = <String>{};
    for (final repo in _repos) {
      final result = await Process.run(
        'git',
        ['branch', '-a', '--format=%(refname)'],
        workingDirectory: repo.path,
        runInShell: true,
      );
      if (result.exitCode == 0) {
        for (final line in LineSplitter.split(result.stdout as String)) {
          final trimmed = line.trim();
          if (trimmed.startsWith('refs/heads/')) {
            allBranches.add(trimmed.replaceFirst('refs/heads/', ''));
          } else if (trimmed.startsWith('refs/remotes/origin/') &&
              !trimmed.endsWith('/HEAD')) {
            allBranches
                .add(trimmed.replaceFirst('refs/remotes/origin/', ''));
          }
        }
      }
    }
    final sortedBranches = allBranches.toList()..sort();

    if (!mounted) return;
    final branch = await showDialog<String>(
      context: context,
      builder: (ctx) => _BranchPickerDialog(
        branches: sortedBranches,
        controller: controller,
        branchColor: _branchColor,
      ),
    );
    controller.dispose();
    if (branch == null || branch.isEmpty) return;

    final selected = _repos.where((r) => r.selected).toList();
    if (selected.isEmpty) return;
    setState(() => _running = true);
    for (final repo in selected) {
      _addLine(
          '\x1B[0;34m[*] Switching ${repo.name} to $branch...\x1B[0m');
      // Try checkout existing branch first
      var result = await Process.run(
        'git',
        ['checkout', branch],
        workingDirectory: repo.path,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        // Try creating new branch from remote
        result = await Process.run(
          'git',
          ['checkout', '-b', branch, 'origin/$branch'],
          workingDirectory: repo.path,
          runInShell: true,
        );
      }
      if (result.exitCode != 0) {
        // Create new local branch
        result = await Process.run(
          'git',
          ['checkout', '-b', branch],
          workingDirectory: repo.path,
          runInShell: true,
        );
      }
      if (result.exitCode == 0) {
        _addLine(
            '\x1B[0;32m[+] ${repo.name}: switched to $branch\x1B[0m');
      } else {
        final err = (result.stderr as String).trim();
        _addLine('\x1B[0;31m[-] ${repo.name}: failed — $err\x1B[0m');
      }
      await _loadRepoStatus(repo);
    }
    if (mounted) setState(() => _running = false);
  }

  // ── Per-repo actions ──

  Future<void> _pullSingle(_RepoInfo repo) async {
    setState(() => _running = true);
    _addLine('\x1B[0;34m[*] Pulling ${repo.name}...\x1B[0m');
    final process = await Process.start(
      'git',
      ['pull'],
      workingDirectory: repo.path,
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
    if (exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${repo.name}: done\x1B[0m');
    } else {
      _addLine(
          '\x1B[0;31m[-] ${repo.name}: failed (exit $exitCode)\x1B[0m');
    }
    await _loadRepoStatus(repo);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _pushSingle(_RepoInfo repo) async {
    setState(() => _running = true);
    _addLine('\x1B[0;36m[>] Pushing ${repo.name}...\x1B[0m');
    final process = await Process.start(
      'git',
      ['push'],
      workingDirectory: repo.path,
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
    if (exitCode == 0) {
      _addLine('\x1B[0;32m[+] ${repo.name}: pushed\x1B[0m');
    } else {
      _addLine('\x1B[0;31m[-] ${repo.name}: push failed\x1B[0m');
    }
    await _loadRepoStatus(repo);
    if (mounted) setState(() => _running = false);
  }

  // ── ANSI parsing ──

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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth =
        screenWidth > 1000 ? AppDialog.widthXl : AppDialog.widthLg;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.workspaces),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(context.l10n.workspaceViewTitle(widget.projectName)),
          ),
          IconButton(
            onPressed: _running ? null : _loadPinnedRepos,
            icon: const Icon(Icons.refresh),
            tooltip: context.l10n.refresh,
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: AppDialog.heightXl,
        child: Column(
          children: [
            // Add repo bar
            _buildAddRepoBar(),
            const SizedBox(height: AppSpacing.sm),
            // Toolbar (select all + batch actions)
            _buildToolbar(),
            const SizedBox(height: AppSpacing.sm),
            // Pinned repo list
            Expanded(child: _buildRepoList()),
            // Log output
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildLogOutput(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  Widget _buildAddRepoBar() {
    final available = _availableToAdd;

    return RawAutocomplete<String>(
      textEditingController: _addRepoController,
      focusNode: _addRepoFocusNode,
      optionsBuilder: (textEditingValue) {
        // Hiện toàn bộ danh sách khi focus, lọc khi gõ
        final q = textEditingValue.text.toLowerCase();
        if (q.isEmpty) return available;
        return available.where((n) => n.toLowerCase().contains(q));
      },
      onSelected: (name) {
        _addRepo(name);
        _addRepoController.clear();
        // Giữ focus để tiếp tục thêm
        _addRepoFocusNode.requestFocus();
      },
      fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
        return SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              hintText: context.l10n.gitSearchRepo,
              prefixIcon:
                  const Icon(Icons.add_circle_outline, size: AppIconSize.md),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_repos.length} / ${_allRepoNames.length}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: AppFontSize.sm,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Dropdown toggle
                  IconButton(
                    onPressed: () {
                      if (focusNode.hasFocus) {
                        focusNode.unfocus();
                      } else {
                        focusNode.requestFocus();
                      }
                    },
                    icon: const Icon(Icons.arrow_drop_down,
                        size: AppIconSize.lg),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: AppRadius.mediumBorderRadius,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 300,
                maxWidth: MediaQuery.of(ctx).size.width * 0.5,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final name = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.add_circle_outline,
                      size: AppIconSize.md,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    onTap: () => onSelected(name),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    final hasSelection = _selectedCount > 0;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Select all / deselect
        TextButton.icon(
          onPressed: _running || _repos.isEmpty
              ? null
              : () => _toggleAll(_selectedCount < _repos.length),
          icon: Icon(
            _selectedCount == _repos.length
                ? Icons.deselect
                : Icons.select_all,
            size: AppIconSize.md,
          ),
          label: Text(
            _selectedCount == _repos.length
                ? context.l10n.gitDeselectAll
                : context.l10n.gitSelectAll,
          ),
        ),
        // Batch actions
        FilledButton.tonalIcon(
          onPressed: _running || !hasSelection ? null : _pullSelected,
          icon: const Icon(Icons.sync, size: AppIconSize.md),
          label: Text(context.l10n.workspaceViewPullSelected),
        ),
        FilledButton.tonalIcon(
          onPressed: _running || !hasSelection ? null : _openCommitDialog,
          icon: const Icon(Icons.commit, size: AppIconSize.md),
          label: Text(context.l10n.gitCommit),
        ),
        FilledButton.tonalIcon(
          onPressed: _running || !hasSelection ? null : _switchBranchAll,
          icon: const Icon(Icons.account_tree, size: AppIconSize.md),
          label: Text(context.l10n.workspaceViewSwitchBranch),
        ),
      ],
    );
  }

  Widget _buildRepoList() {
    if (_scanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l10n.workspaceViewScanning,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_repos.isEmpty) {
      return Center(
        child: Text(
          context.l10n.workspaceViewNoRepos,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _repos.length,
      itemBuilder: (ctx, i) => _buildRepoTile(_repos[i]),
    );
  }

  Widget _buildRepoTile(_RepoInfo repo) {
    return Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: InkWell(
          onTap: _running
              ? null
              : () {
                  setState(() => repo.selected = !repo.selected);
                  _saveSelection();
                },
          borderRadius: AppRadius.mediumBorderRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
            children: [
              // Checkbox
              Checkbox(
                value: repo.selected,
                onChanged: _running
                    ? null
                    : (v) {
                        setState(() => repo.selected = v ?? false);
                        _saveSelection();
                      },
              ),
              const SizedBox(width: AppSpacing.md),
              // Repo name
              Expanded(
                flex: 3,
                child: Text(
                  repo.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: AppFontSize.lg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Branch chip
              if (repo.branch.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _branchColor(repo.branch).withValues(alpha: 0.15),
                    borderRadius: AppRadius.smallBorderRadius,
                  ),
                  child: Text(
                    repo.branch,
                    style: TextStyle(
                      fontSize: AppFontSize.md,
                      fontFamily: 'monospace',
                      color: _branchColor(repo.branch),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.md),
              // Status indicators
              if (repo.changedFiles > 0)
                _statusBadge(
                  '${repo.changedFiles} \u2191',
                  Colors.orange,
                ),
              if (repo.aheadCount > 0)
                _statusBadge(
                  '${repo.aheadCount} \u2191',
                  Colors.green,
                ),
              if (repo.behindCount > 0)
                _statusBadge(
                  '${repo.behindCount} \u2193',
                  Colors.cyan,
                ),
              // Per-repo actions
              const SizedBox(width: AppSpacing.md),
              _repoActionButton(
                icon: Icons.sync,
                tooltip: context.l10n.gitPull,
                onPressed: () => _pullSingle(repo),
              ),
              _repoActionButton(
                icon: Icons.upload,
                tooltip: 'Push',
                onPressed: repo.aheadCount > 0
                    ? () => _pushSingle(repo)
                    : null,
              ),
              // Remove from workspace
              _repoActionButton(
                icon: Icons.close,
                tooltip: context.l10n.removeFromList,
                onPressed: () => _removeRepo(repo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: AppRadius.smallBorderRadius,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontFamily: 'monospace',
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _repoActionButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: _running ? null : onPressed,
      icon: Icon(icon, size: AppIconSize.lg),
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

  Widget _buildLogOutput() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppLogColors.terminalBg,
        borderRadius: AppRadius.mediumBorderRadius,
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: SelectionArea(
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
    );
  }
}

// ── Branch Picker Dialog ──

class _BranchPickerDialog extends StatefulWidget {
  final List<String> branches;
  final TextEditingController controller;
  final Color Function(String) branchColor;

  const _BranchPickerDialog({
    required this.branches,
    required this.controller,
    required this.branchColor,
  });

  @override
  State<_BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends State<_BranchPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? widget.branches
        : widget.branches
            .where((b) => b.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return AlertDialog(
      title: Text(context.l10n.workspaceViewSwitchBranch),
      content: SizedBox(
        width: AppDialog.widthSm,
        height: AppDialog.heightMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search / create
            TextField(
              controller: widget.controller,
              decoration: InputDecoration(
                hintText: context.l10n.workspaceViewNewBranch,
                prefixIcon:
                    const Icon(Icons.search, size: AppIconSize.md),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Branch list
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final branch = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.account_tree,
                      size: AppIconSize.md,
                      color: widget.branchColor(branch),
                    ),
                    title: Text(
                      branch,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: widget.branchColor(branch),
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, branch),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        if (widget.controller.text.trim().isNotEmpty)
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, widget.controller.text.trim()),
            child: Text(context.l10n.workspaceViewCreateBranch),
          ),
      ],
    );
  }
}

// ── Workspace Commit Dialog ──

class _WorkspaceCommitDialog extends StatefulWidget {
  final List<_RepoInfo> repos;
  final VoidCallback onDone;

  const _WorkspaceCommitDialog({
    required this.repos,
    required this.onDone,
  });

  @override
  State<_WorkspaceCommitDialog> createState() =>
      _WorkspaceCommitDialogState();
}

class _WorkspaceCommitDialogState extends State<_WorkspaceCommitDialog> {
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

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _logLines = [];
  bool _running = false;
  bool _pushAfterCommit = true;

  @override
  void dispose() {
    _messageController.dispose();
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

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() => _running = true);
    for (final repo in widget.repos) {
      _addLine('\x1B[0;34m[*] Committing ${repo.name}...\x1B[0m');

      // git add -A
      final addResult = await Process.run(
        'git',
        ['add', '-A'],
        workingDirectory: repo.path,
        runInShell: true,
      );
      if (addResult.exitCode != 0) {
        _addLine(
            '\x1B[0;31m[-] git add failed: ${addResult.stderr}\x1B[0m');
        continue;
      }

      // git commit
      final commitResult = await Process.run(
        'git',
        ['commit', '-m', message],
        workingDirectory: repo.path,
        runInShell: true,
      );
      final commitOut = (commitResult.stdout as String).trim();
      if (commitOut.isNotEmpty) _addLine(commitOut);
      if (commitResult.exitCode != 0) {
        final errOut = (commitResult.stderr as String).trim();
        if (errOut.isNotEmpty) _addLine('\x1B[0;31m$errOut\x1B[0m');
        continue;
      }

      // git push (optional)
      if (_pushAfterCommit) {
        _addLine('\x1B[0;36m[>] Pushing ${repo.name}...\x1B[0m');
        final pushProcess = await Process.start(
          'git',
          ['push'],
          workingDirectory: repo.path,
          runInShell: true,
        );
        pushProcess.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (mounted) _addLine(line);
        });
        pushProcess.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (mounted) _addLine(line);
        });
        final pushExit = await pushProcess.exitCode;
        if (pushExit != 0) {
          _addLine(
              '\x1B[0;31m[-] Push failed for ${repo.name}\x1B[0m');
        }
      }

      _addLine('\x1B[0;32m[+] ${repo.name}: committed\x1B[0m');
    }
    widget.onDone();
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
    final canCommit =
        !_running && _messageController.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(context.l10n.gitCommitTitle(
          '${widget.repos.length} repos')),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Repo list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.repos.length,
                itemBuilder: (ctx, i) {
                  final repo = widget.repos[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.folder,
                        size: AppIconSize.md, color: Colors.orange),
                    title: Text(repo.name,
                        style: const TextStyle(fontSize: AppFontSize.md)),
                    trailing: Text(
                      '${repo.changedFiles} file(s)',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Commit message
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: context.l10n.gitCommitMessage,
                hintText: context.l10n.gitCommitMessageHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Push after commit
            GestureDetector(
              onTap: () =>
                  setState(() => _pushAfterCommit = !_pushAfterCommit),
              child: Row(
                children: [
                  Checkbox(
                    value: _pushAfterCommit,
                    onChanged: (v) =>
                        setState(() => _pushAfterCommit = v ?? true),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    context.l10n.gitPushAfterCommit,
                    style: const TextStyle(fontSize: AppFontSize.sm),
                  ),
                ],
              ),
            ),
            // Log output
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppLogColors.terminalBg,
                  borderRadius: AppRadius.mediumBorderRadius,
                  border: Border.all(color: Colors.grey.shade700),
                ),
                child: SelectionArea(
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        FilledButton.icon(
          onPressed: canCommit ? _commit : null,
          icon: const Icon(Icons.check, size: AppIconSize.md),
          label: Text(
            _pushAfterCommit
                ? context.l10n.workspaceViewCommitPush
                : context.l10n.workspaceViewCommitOnly,
          ),
        ),
      ],
    );
  }
}
