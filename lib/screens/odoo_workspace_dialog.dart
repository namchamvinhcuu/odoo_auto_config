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
  bool loaded = false;

  _RepoInfo({
    required this.name,
    required this.path,
  });
}

/// Number of repos to load per batch
const _kBatchSize = 8;

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
  /// All repo names found in addons/ (for search/add)
  List<String> _allRepoNames = [];

  /// Pinned repos (persisted, shown in main list)
  final List<_RepoInfo> _repos = [];

  final _addRepoController = TextEditingController();
  final _addRepoFocusNode = FocusNode();
  final _scrollController = ScrollController();
  bool _scanning = true;
  bool _loadingMore = false;

  String get _storageKey => 'workspaceRepos_${widget.projectPath}';
  String get _selectionKey => 'workspaceSelected_${widget.projectPath}';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPinnedRepos();
  }

  @override
  void dispose() {
    _addRepoController.dispose();
    _addRepoFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore) return;
    final pos = _scrollController.position;
    // Load next batch when scrolled within 200px of the bottom
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadNextBatch();
    }
  }

  // ── Data loading ──

  /// Load pinned repos. [loadAll] = true loads all statuses (refresh),
  /// false loads first batch only (initial open).
  Future<void> _loadPinnedRepos({bool loadAll = false}) async {
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

      if (mounted) setState(() => _scanning = false);

      if (loadAll) {
        // Refresh: load ALL statuses in parallel
        if (_repos.isNotEmpty) {
          await Future.wait(_repos.map(_loadRepoStatus));
        }
      } else {
        // Initial open: load first batch only
        await _loadNextBatch();
      }
    } catch (e) {
      // Error scanning repos — ignore silently
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _loadNextBatch() async {
    if (_loadingMore) return;
    final unloaded = _repos.where((r) => !r.loaded).take(_kBatchSize).toList();
    if (unloaded.isEmpty) return;

    _loadingMore = true;
    if (mounted) setState(() {});

    await Future.wait(unloaded.map(_loadRepoStatus));

    _loadingMore = false;
    if (mounted) setState(() {});
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

    repo.loaded = true;
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

  void _pullSelected() {
    final selected = _repos.where((r) => r.selected).toList();
    if (selected.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => _GitActionDialog(
        title: context.l10n.workspaceViewPullSelected,
        repos: selected,
        action: 'pull',
        onDone: () {
          for (final repo in selected) {
            _loadRepoStatus(repo);
          }
        },
      ),
    );
  }

  void _openCommitDialog() {
    final reposWithChanges = _repos
        .where((r) => r.selected && r.changedFiles > 0)
        .toList();

    if (reposWithChanges.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.grey,
                  size: AppIconSize.xxl),
              const Spacer(),
              AppDialog.closeButton(ctx),
            ],
          ),
          content: Text(
            context.l10n.gitCommitNoChanges,
            textAlign: TextAlign.center,
          ),
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

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _GitActionDialog(
        title: '${context.l10n.workspaceViewSwitchBranch} → $branch',
        repos: selected,
        action: 'switch',
        branch: branch,
        onDone: () {
          for (final repo in selected) {
            _loadRepoStatus(repo);
          }
        },
      ),
    );
  }

  // ── Per-repo actions ──

  void _pullSingle(_RepoInfo repo) {
    showDialog(
      context: context,
      builder: (ctx) => _GitActionDialog(
        title: '${context.l10n.gitPull} — ${repo.name}',
        repos: [repo],
        action: 'pull',
        onDone: () => _loadRepoStatus(repo),
      ),
    );
  }

  void _pushSingle(_RepoInfo repo) {
    showDialog(
      context: context,
      builder: (ctx) => _GitActionDialog(
        title: 'Push — ${repo.name}',
        repos: [repo],
        action: 'push',
        onDone: () => _loadRepoStatus(repo),
      ),
    );
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
          const Spacer(),
          IconButton(
            onPressed: () => _loadPinnedRepos(loadAll: true),
            icon: const Icon(Icons.refresh, color: Colors.white, size: AppIconSize.md),
            style: IconButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
              padding: EdgeInsets.zero,
            ),
            tooltip: context.l10n.refresh,
          ),
          const SizedBox(width: AppSpacing.sm),
          AppDialog.closeButton(context),
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
          ],
        ),
      ),
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

  void _openPublishDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PublishModulesDialog(
        projectPath: widget.projectPath,
      ),
    ).then((_) => _loadPinnedRepos(loadAll: true));
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
          onPressed: _repos.isEmpty
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
          onPressed: hasSelection ? _pullSelected : null,
          icon: const Icon(Icons.sync, size: AppIconSize.md),
          label: Text(context.l10n.workspaceViewPullSelected),
        ),
        FilledButton.tonalIcon(
          onPressed: hasSelection ? _openCommitDialog : null,
          icon: const Icon(Icons.commit, size: AppIconSize.md),
          label: Text(context.l10n.gitCommit),
        ),
        FilledButton.tonalIcon(
          onPressed: hasSelection ? _switchBranchAll : null,
          icon: const Icon(Icons.account_tree, size: AppIconSize.md),
          label: Text(context.l10n.workspaceViewSwitchBranch),
        ),
        FilledButton.tonalIcon(
          onPressed: _openPublishDialog,
          icon: const Icon(Icons.cloud_upload, size: AppIconSize.md),
          label: Text(context.l10n.publishModules),
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

    final hasMore = _repos.any((r) => !r.loaded);
    return ListView.builder(
      controller: _scrollController,
      itemCount: _repos.length + (hasMore || _loadingMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= _repos.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _buildRepoTile(_repos[i]);
      },
    );
  }

  Widget _buildRepoTile(_RepoInfo repo) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: () {
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
                onChanged: (v) {
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
              // Loading placeholder or status
              if (!repo.loaded)
                const SizedBox(
                  width: AppIconSize.md,
                  height: AppIconSize.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
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
                  tooltip: context.l10n.push,
                  onPressed: repo.aheadCount > 0
                      ? () => _pushSingle(repo)
                      : null,
                ),
              ],
              // Remove from workspace (always visible)
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
      onPressed: onPressed,
      icon: Icon(icon, size: AppIconSize.lg),
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
      title: Row(
        children: [
          Text(context.l10n.workspaceViewSwitchBranch),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
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
      title: Row(
        children: [
          Expanded(
            child: Text(context.l10n.gitCommitTitle(
                '${widget.repos.length} repos')),
          ),
          AppDialog.closeButton(context,
              onClose: _running ? null : () => Navigator.pop(context)),
        ],
      ),
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

// ── Git Action Dialog (Pull / Push / Switch Branch) ──

class _GitActionDialog extends StatefulWidget {
  final String title;
  final List<_RepoInfo> repos;

  /// 'pull', 'push', or 'switch'
  final String action;
  final String? branch;
  final VoidCallback onDone;

  const _GitActionDialog({
    required this.title,
    required this.repos,
    required this.action,
    this.branch,
    required this.onDone,
  });

  @override
  State<_GitActionDialog> createState() => _GitActionDialogState();
}

class _GitActionDialogState extends State<_GitActionDialog> {
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
      }
    }
    widget.onDone();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _pullRepo(_RepoInfo repo) async {
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

  Future<void> _pushRepo(_RepoInfo repo) async {
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

  Future<void> _switchRepo(_RepoInfo repo, String branch) async {
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
          AppDialog.closeButton(context,
              onClose: _running ? null : () => Navigator.pop(context)),
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

// ── Publish Modules Dialog ──

/// .gitignore template for Odoo modules
const _odooGitignore = r'''# Byte-compiled / optimized / DLL files
models/__pycache__/
*.py[cod]
*$py.class

# C extensions
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# PyInstaller
*.manifest
*.spec

# Installer logs
pip-log.txt
pip-delete-this-directory.txt

# Unit test / coverage reports
htmlcov/
.tox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
.hypothesis/
.pytest_cache/

# Translations
*.mo
*.pot

# Django stuff:
*.log
local_settings.py
db.sqlite3

# Flask stuff:
instance/
.webassets-cache

# Scrapy stuff:
.scrapy

# Sphinx documentation
docs/_build/

# PyBuilder
target/

# Jupyter Notebook
.ipynb_checkpoints

# pyenv
.python-version

# celery beat schedule file
celerybeat-schedule

# SageMath parsed files
*.sage.py

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Spyder project settings
.spyderproject
.spyproject

# Rope project settings
.ropeproject

# mkdocs documentation
/site

# mypy
.mypy_cache/

# sphinx build directories
_build/

# dotfiles
.*
!.gitignore
!.github
!.mailmap
# compiled python files
*.py[co]
__pycache__/
# setup.py egg_info
*.egg-info
# emacs backup files
*~
# hg stuff
*.orig
status
# odoo filestore
odoo/filestore
# maintenance migration scripts
odoo/addons/base/maintenance

# generated for windows installer?
install/win32/*.bat
install/win32/meta.py

# needed only when building for win32
setup/win32/static/less/
setup/win32/static/wkhtmltopdf/
setup/win32/static/postgresql*.exe

# js tooling
node_modules
jsconfig.json
tsconfig.json
package-lock.json
package.json
.husky

# various virtualenv
/bin/
/build/
/dist/
/include/
/man/
/share/
/src/
*.pyc
''';

class _PublishModulesDialog extends StatefulWidget {
  final String projectPath;

  const _PublishModulesDialog({required this.projectPath});

  @override
  State<_PublishModulesDialog> createState() => _PublishModulesDialogState();
}

class _PublishModulesDialogState extends State<_PublishModulesDialog> {
  List<String> _modules = [];
  final Set<String> _selected = {};
  bool _scanning = true;
  bool _publishing = false;
  final List<TextSpan> _logSpans = [];
  String? _error;

  // Git config
  String _gitOrg = '';
  String _gitToken = '';

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      // Read git-org from script file
      final shPath = p.join(widget.projectPath, 'git-repositories.sh');
      final ps1Path = p.join(widget.projectPath, 'git-repositories.ps1');
      final scriptFile = await File(shPath).exists()
          ? File(shPath)
          : (await File(ps1Path).exists() ? File(ps1Path) : null);

      if (scriptFile != null) {
        final content = await scriptFile.readAsString();
        final orgMatch =
            RegExp(r'ORG_NAME\s*=\s*"([^"]*)"').firstMatch(content);
        _gitOrg = orgMatch?.group(1) ?? '';
      }

      // Read token from git accounts
      final settings = await StorageService.loadSettings();
      if (scriptFile != null) {
        final content = await scriptFile.readAsString();
        final tokenMatch =
            RegExp(r'TOKEN\s*=\s*"([^"]*)"').firstMatch(content);
        final scriptToken = tokenMatch?.group(1) ?? '';
        // Match token to account, or use script token directly
        final accounts = (settings['gitAccounts'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final matchedAccount = accounts
            .where((a) => a['token'] == scriptToken)
            .firstOrNull;
        _gitToken = matchedAccount?['token']?.toString() ??
            scriptToken;
      }
      if (_gitToken.isEmpty) {
        // Fallback: use default account token
        final accounts = (settings['gitAccounts'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final defaultName =
            (settings['defaultGitAccount'] ?? '').toString();
        final def = accounts
            .where((a) => a['name'] == defaultName)
            .firstOrNull;
        _gitToken = def?['token']?.toString() ?? '';
      }

      // Validate
      if (_gitOrg.isEmpty ||
          _gitOrg == 'YOUR_ORGANIZATION') {
        setState(() {
          _scanning = false;
          _error = context.l10n.publishModulesNoOrg;
        });
        return;
      }
      if (_gitToken.isEmpty ||
          _gitToken == 'YOUR_GITHUB_TOKEN') {
        setState(() {
          _scanning = false;
          _error = context.l10n.publishModulesNoToken;
        });
        return;
      }

      // Scan addons/ for dirs WITHOUT .git
      final addonsDir =
          Directory(p.join(widget.projectPath, 'addons'));
      final modules = <String>[];
      if (await addonsDir.exists()) {
        await for (final entity in addonsDir.list()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue;
            final gitDir = Directory(p.join(entity.path, '.git'));
            if (!await gitDir.exists()) {
              modules.add(name);
            }
          }
        }
      }
      modules.sort();

      setState(() {
        _modules = modules;
        _scanning = false;
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _error = e.toString();
      });
    }
  }

  void _addLog(String text, {Color color = Colors.white70}) {
    setState(() {
      _logSpans.add(TextSpan(
        text: '$text\n',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: AppFontSize.md,
          color: color,
        ),
      ));
    });
    // Auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _publish() async {
    if (_selected.isEmpty) return;

    // Cache l10n strings before async gaps
    final l10n = context.l10n;

    setState(() {
      _publishing = true;
      _logSpans.clear();
    });

    for (final name in _selected.toList()) {
      final modulePath = p.join(widget.projectPath, 'addons', name);

      _addLog(l10n.publishModulesCreatingRepo(name),
          color: Colors.cyan);

      // 1. Create .gitignore if missing
      final gitignoreFile = File(p.join(modulePath, '.gitignore'));
      if (!await gitignoreFile.exists()) {
        await gitignoreFile.writeAsString(_odooGitignore);
        _addLog('  [+] .gitignore', color: Colors.green);
      }

      // 2. Create README.md if missing
      final readmeFile = File(p.join(modulePath, 'README.md'));
      if (!await readmeFile.exists()) {
        await readmeFile.writeAsString('# $name\n');
        _addLog('  [+] README.md', color: Colors.green);
      }

      // 3. Create GitHub repo via API
      try {
        final result = await Process.run(
          'curl',
          [
            '-s',
            '-w', r'\n%{http_code}',
            '-X', 'POST',
            '-H', 'Authorization: token $_gitToken',
            '-H', 'Accept: application/vnd.github.v3+json',
            '-d', jsonEncode({
              'name': name,
              'private': true,
              'auto_init': false,
            }),
            'https://api.github.com/orgs/$_gitOrg/repos',
          ],
          runInShell: true,
        );

        final output = (result.stdout as String).trimRight();
        final lines = output.split('\n');
        final httpCode = lines.last.trim();
        final body = lines.sublist(0, lines.length - 1).join('\n');

        if (httpCode != '201') {
          // Check if repo already exists (422)
          if (httpCode == '422' && body.contains('already exists')) {
            _addLog('  [!] Repo already exists on GitHub, continuing...',
                color: Colors.orange);
          } else {
            final parsed = jsonDecode(body);
            final msg = parsed['message'] ?? 'HTTP $httpCode';
            _addLog(
              l10n.publishModulesFailed(name, msg.toString()),
              color: Colors.red,
            );
            continue;
          }
        } else {
          _addLog('  [+] GitHub repo created', color: Colors.green);
        }

        // 4. git init + add + commit + remote + push
        final commands = [
          ['git', 'init'],
          ['git', 'add', '-A'],
          ['git', 'commit', '-m', 'Initial commit'],
          [
            'git',
            'remote',
            'add',
            'origin',
            'https://$_gitToken@github.com/$_gitOrg/$name.git',
          ],
          ['git', 'branch', '-M', 'main'],
          ['git', 'push', '-u', 'origin', 'main'],
        ];

        var success = true;
        for (final cmd in commands) {
          final r = await Process.run(
            cmd.first,
            cmd.sublist(1),
            workingDirectory: modulePath,
            runInShell: true,
          );
          if (r.exitCode != 0) {
            final stderr = (r.stderr as String).trimRight();
            // remote add fails if already exists — skip
            if (cmd[1] == 'remote' && stderr.contains('already exists')) {
              _addLog('  [!] Remote origin already exists, updating...',
                  color: Colors.orange);
              await Process.run(
                'git',
                [
                  'remote',
                  'set-url',
                  'origin',
                  'https://$_gitToken@github.com/$_gitOrg/$name.git',
                ],
                workingDirectory: modulePath,
                runInShell: true,
              );
              continue;
            }
            _addLog('  [✗] ${cmd.join(' ')}', color: Colors.red);
            if (stderr.isNotEmpty) {
              _addLog('      $stderr', color: Colors.red);
            }
            success = false;
            break;
          } else {
            _addLog('  [✓] ${cmd.join(' ')}', color: Colors.green);
          }
        }

        if (success) {
          _addLog(
            l10n.publishModulesSuccess(name),
            color: Colors.greenAccent,
          );
        }
      } catch (e) {
        _addLog(
          l10n.publishModulesFailed(name, e.toString()),
          color: Colors.red,
        );
      }
    }

    _addLog('\nDone.', color: Colors.white);
    if (mounted) setState(() => _publishing = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.cloud_upload),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(context.l10n.publishModules),
          ),
          const Spacer(),
          AppDialog.closeButton(context, onClose: _publishing ? null : null),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        height: AppDialog.heightXl,
        child: _scanning
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.publishModulesScanning,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: AppIconSize.xxl),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  )
                : _modules.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.publishModulesNoModules,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info bar
                          Text(
                            '${context.l10n.publishModulesSelect}'
                            '  •  org: $_gitOrg'
                            '  •  ${_modules.length} modules',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: AppFontSize.md,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // Module list
                          if (!_publishing)
                            Expanded(
                              child: ListView.builder(
                                itemCount: _modules.length,
                                itemBuilder: (ctx, i) {
                                  final name = _modules[i];
                                  final checked =
                                      _selected.contains(name);
                                  return ListTile(
                                    dense: true,
                                    leading: Checkbox(
                                      value: checked,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selected.add(name);
                                          } else {
                                            _selected.remove(name);
                                          }
                                        });
                                      },
                                    ),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        if (checked) {
                                          _selected.remove(name);
                                        } else {
                                          _selected.add(name);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          // Log output (shown during/after publish)
                          if (_logSpans.isNotEmpty)
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                    AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius:
                                      AppRadius.mediumBorderRadius,
                                ),
                                child: SelectionArea(
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    child: Text.rich(
                                      TextSpan(children: _logSpans),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
      actions: _error != null || _scanning || _modules.isEmpty
          ? null
          : [
              if (!_publishing)
                FilledButton.icon(
                  onPressed:
                      _selected.isEmpty ? null : _publish,
                  icon: const Icon(Icons.cloud_upload,
                      size: AppIconSize.md),
                  label: Text(
                    '${context.l10n.publishModulesPublish}'
                    ' (${_selected.length})',
                  ),
                ),
              if (_publishing)
                const SizedBox(
                  width: AppIconSize.lg,
                  height: AppIconSize.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
    );
  }
}
