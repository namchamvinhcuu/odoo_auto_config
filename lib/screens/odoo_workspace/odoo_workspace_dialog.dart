import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'repo_info.dart';
import 'repo_branch_dialog.dart';
import 'branch_picker_dialog.dart';
import 'workspace_commit_dialog.dart';
import 'git_action_dialog.dart';
import 'publish_modules_dialog.dart';

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
  final List<RepoInfo> _repos = [];

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
        final repo = RepoInfo(
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

  Future<void> _loadRepoStatus(RepoInfo repo) async {
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
      repo.hasUpstream = true;
    } else {
      repo.hasUpstream = false;
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
    await StorageService.updateSettings((settings) {
      settings[_storageKey] = _repos.map((r) => r.name).toList();
      settings[_selectionKey] =
          _repos.where((r) => r.selected).map((r) => r.name).toList();
    });
  }

  Future<void> _saveSelection() async {
    await StorageService.updateSettings((settings) {
      settings[_selectionKey] =
          _repos.where((r) => r.selected).map((r) => r.name).toList();
    });
  }

  Future<void> _addRepo(String name) async {
    if (_repos.any((r) => r.name == name)) return;
    final repo = RepoInfo(
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

  Future<void> _removeRepo(RepoInfo repo) async {
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
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
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
      AppDialog.show(
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

    AppDialog.show(
      context: context,
      builder: (ctx) => WorkspaceCommitDialog(
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

  // ignore: unused_element — hidden feature, kept for future use
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
    final branch = await AppDialog.show<String>(
      context: context,
      builder: (ctx) => BranchPickerDialog(
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
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
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

  void _pullSingle(RepoInfo repo) {
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
        title: '${context.l10n.gitPull} — ${repo.name}',
        repos: [repo],
        action: 'pull',
        onDone: () => _loadRepoStatus(repo),
      ),
    );
  }

  void _pushSingle(RepoInfo repo) {
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
        title: 'Push — ${repo.name}',
        repos: [repo],
        action: 'push',
        onDone: () => _loadRepoStatus(repo),
      ),
    );
  }

  void _openRepoBranchDialog(RepoInfo repo) {
    AppDialog.show(
      context: context,
      builder: (ctx) => RepoBranchDialog(
        repoName: repo.name,
        repoPath: repo.path,
        currentBranch: repo.branch,
        branchColor: _branchColor,
        onChanged: (branch) {
          repo.branch = branch;
          if (mounted) setState(() {});
        },
      ),
    ).then((_) => _loadRepoStatus(repo));
  }

  void _publishSingle(RepoInfo repo) {
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
        title:
            '${context.l10n.gitBranchPublish(repo.branch)} — ${repo.name}',
        repos: [repo],
        action: 'publish',
        onDone: () => _loadRepoStatus(repo),
      ),
    );
  }

  void _publishSelected() {
    final selected =
        _repos.where((r) => r.selected && !r.hasUpstream).toList();
    if (selected.isEmpty) return;
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
        title: context.l10n.workspaceViewPublishBranch,
        repos: selected,
        action: 'publish',
        onDone: () {
          for (final repo in selected) {
            _loadRepoStatus(repo);
          }
        },
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
          AppDialog.closeButton(context, enabled: !_scanning),
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
    AppDialog.show(
      context: context,
      builder: (ctx) => PublishModulesDialog(
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
        // Switch Branch All — hidden (code kept for future use)
        // FilledButton.tonalIcon(
        //   onPressed: hasSelection ? _switchBranchAll : null,
        //   icon: const Icon(Icons.account_tree, size: AppIconSize.md),
        //   label: Text(context.l10n.workspaceViewSwitchBranch),
        // ),
        if (_repos.any((r) => r.selected && !r.hasUpstream))
          FilledButton.tonalIcon(
            onPressed: _publishSelected,
            icon: const Icon(Icons.cloud_upload, size: AppIconSize.md),
            label: Text(context.l10n.workspaceViewPublishBranch),
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

  Widget _buildRepoTile(RepoInfo repo) {
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
                // Branch chip (clickable → open branch dialog)
                if (repo.branch.isNotEmpty)
                  InkWell(
                    onTap: () => _openRepoBranchDialog(repo),
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: AppRadius.smallBorderRadius,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: _branchColor(repo.branch)
                            .withValues(alpha: 0.15),
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
                if (!repo.hasUpstream)
                  _repoActionButton(
                    icon: Icons.cloud_upload,
                    tooltip: context.l10n.gitBranchPublish(repo.branch),
                    color: Colors.green,
                    onPressed: () => _publishSingle(repo),
                  )
                else
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
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: AppIconSize.lg, color: onPressed != null ? color : null),
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }

}
