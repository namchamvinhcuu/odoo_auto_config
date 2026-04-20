import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'package:odoo_auto_config/widgets/clone_repository_dialog.dart';
import 'package:odoo_auto_config/widgets/vscode_install_dialog.dart';
import 'repo_info.dart';
import 'repo_branch_dialog.dart';
import 'branch_picker_dialog.dart';
import 'workspace_commit_dialog.dart';
import 'git_action_dialog.dart';
import 'repo_commit_dialog.dart';
import 'repo_create_pr_dialog.dart';
import 'publish_modules_dialog.dart';

/// Number of repos to load per batch
const _kBatchSize = 8;
const _kSearchItemExtent = 40.0;
const _kSearchMaxVisibleItems = 5;

/// Odoo Workspace View — dashboard for managing pinned repos in addons/
class OdooWorkspaceDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;
  final String? nginxSubdomain;

  const OdooWorkspaceDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
    this.nginxSubdomain,
  });

  bool get hasNginx =>
      nginxSubdomain != null && nginxSubdomain!.isNotEmpty;

  @override
  State<OdooWorkspaceDialog> createState() => _OdooWorkspaceDialogState();
}

class _OdooWorkspaceDialogState extends State<OdooWorkspaceDialog> {
  /// All repo names found under the project root (excluding the root repo itself)
  List<String> _allRepoNames = [];

  /// Pinned repos (persisted, shown in main list)
  final List<RepoInfo> _repos = [];
  final Set<String> _addingRepoNames = {};

  final _addRepoController = TextEditingController();
  final _addRepoFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _searchListScrollController = ScrollController();
  bool _scanning = true;
  bool _loadingMore = false;
  bool _isSearchOpen = false;
  int _highlightedIndex = 0;

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
    _searchListScrollController.dispose();
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
    if (mounted) context.setDialogRunning(true);

    try {
      final projectDir = Directory(widget.projectPath);
      final allNames = await _scanProjectRepos(projectDir);
      allNames.sort();
      _allRepoNames = allNames;

      // Load persisted pinned list
      final settings = await StorageService.loadSettings();
      final saved =
          (settings[_storageKey] as List?)
              ?.map((e) => e.toString())
              .where((r) => allNames.contains(r))
              .toList() ??
          [];

      // Load persisted selection
      final selectedSet =
          (settings[_selectionKey] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{};

      // Build _repos from pinned names
      for (final name in saved) {
        final repo = RepoInfo(
          name: name,
          path: p.join(widget.projectPath, name),
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

      if (mounted) context.setDialogRunning(false);
    } catch (e) {
      // Error scanning repos — ignore silently
      if (mounted) {
        setState(() => _scanning = false);
        context.setDialogRunning(false);
      }
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

  Future<List<String>> _scanProjectRepos(Directory projectDir) async {
    final repos = <String>[];
    if (!await projectDir.exists()) return repos;

    Future<void> scanDir(Directory dir) async {
      final gitDir = Directory(p.join(dir.path, '.git'));
      if (await gitDir.exists()) {
        final relative = p.relative(dir.path, from: widget.projectPath);
        if (relative != '.' && relative.isNotEmpty) {
          repos.add(relative);
        }
        return;
      }

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory && p.basename(entity.path) != '.git') {
          await scanDir(entity);
        }
      }
    }

    await for (final entity in projectDir.list(followLinks: false)) {
      if (entity is Directory) {
        await scanDir(entity);
      }
    }

    return repos;
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
      repo.changedFiles = output.isEmpty
          ? 0
          : LineSplitter.split(output).length;
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
      settings[_selectionKey] = _repos
          .where((r) => r.selected)
          .map((r) => r.name)
          .toList();
    });
  }

  Future<void> _saveSelection() async {
    await StorageService.updateSettings((settings) {
      settings[_selectionKey] = _repos
          .where((r) => r.selected)
          .map((r) => r.name)
          .toList();
    });
  }

  Future<void> _addRepo(String name) async {
    if (_repos.any((r) => r.name == name)) return;
    final repo = RepoInfo(name: name, path: p.join(widget.projectPath, name));
    setState(() {
      _repos.add(repo);
      _repos.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    });
    await _savePinnedList();
    await _loadRepoStatus(repo);
  }

  Future<void> _handleRepoSelected(String name) async {
    if (_addingRepoNames.contains(name) || _repos.any((r) => r.name == name)) {
      _resetAddRepoField();
      return;
    }

    setState(() => _addingRepoNames.add(name));
    try {
      await _addRepo(name);
    } finally {
      if (mounted) {
        setState(() => _addingRepoNames.remove(name));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _resetAddRepoField();
          }
        });
      }
    }
  }

  void _resetAddRepoField() {
    _addRepoController.clear();
    setState(() {
      _highlightedIndex = 0;
      _isSearchOpen = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _addRepoFocusNode.requestFocus();
      }
    });
  }

  void _dismissSearchFocus() {
    if (_addRepoFocusNode.hasFocus) {
      _addRepoFocusNode.unfocus();
    }
    if (_isSearchOpen) {
      setState(() => _isSearchOpen = false);
    }
  }

  Future<void> _removeRepo(RepoInfo repo) async {
    setState(() => _repos.remove(repo));
    await _savePinnedList();
  }

  Future<void> _cloneRepoToWorkspace() async {
    _dismissSearchFocus();
    final result = await AppDialog.show<CloneRepositoryResult>(
      context: context,
      builder: (ctx) => CloneRepositoryDialog(
        title: 'Clone Repository to Workspace',
        subtitle:
            'Clone a repository inside this project. Keep the target folder as "addons" for the standard flow, or change it to another folder under the project root.',
        submitLabel: 'Clone to Project',
        initialBaseDir: widget.projectPath,
        allowBaseDirPicker: false,
        showDescription: false,
        baseDirLabel: 'Project Directory',
        baseDirHint: widget.projectPath,
        targetFolderLabel: 'Target Folder',
        initialTargetFolder: 'addons',
      ),
    );
    if (result == null) return;

    final repoKey = p.relative(result.targetDir, from: widget.projectPath);
    if (!_allRepoNames.contains(repoKey)) {
      _allRepoNames.add(repoKey);
      _allRepoNames.sort();
    }
    await _addRepo(repoKey);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cloned "${result.repoName}" into "$repoKey"')),
      );
    }
  }

  // ── Helpers ──

  /// Repo names available to add (not yet pinned)
  List<String> get _availableToAdd {
    final pinnedNames = _repos.map((r) => r.name).toSet();
    return _allRepoNames
        .where((n) => !pinnedNames.contains(n) && !_addingRepoNames.contains(n))
        .toList();
  }

  List<String> get _filteredRepoNames {
    final query = _addRepoController.text.trim().toLowerCase();
    final available = _availableToAdd;
    if (query.isEmpty) return available;
    return available.where((n) => n.toLowerCase().contains(query)).toList();
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
    _dismissSearchFocus();
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
      _dismissSearchFocus();
      AppDialog.show(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Colors.grey,
                size: AppIconSize.xxl,
              ),
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

    _dismissSearchFocus();
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
            allBranches.add(trimmed.replaceFirst('refs/remotes/origin/', ''));
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
    _dismissSearchFocus();
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
    _dismissSearchFocus();
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
    if (repo.changedFiles > 0) {
      // Has uncommitted changes → show commit dialog first
      _dismissSearchFocus();
      AppDialog.show(
        context: context,
        builder: (ctx) =>
            RepoCommitDialog(repoName: repo.name, repoPath: repo.path),
      ).then((_) => _loadRepoStatus(repo));
      return;
    }
    _dismissSearchFocus();
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

  void _createPrSingle(RepoInfo repo) {
    _dismissSearchFocus();
    AppDialog.show(
      context: context,
      builder: (ctx) => RepoCreatePRDialog(
        repoName: repo.name,
        repoPath: repo.path,
        currentBranch: repo.branch,
      ),
    ).then((_) => _loadRepoStatus(repo));
  }

  void _openRepoBranchDialog(RepoInfo repo) {
    _dismissSearchFocus();
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
    _dismissSearchFocus();
    AppDialog.show(
      context: context,
      builder: (ctx) => GitActionDialog(
        title: '${context.l10n.gitBranchPublish(repo.branch)} — ${repo.name}',
        repos: [repo],
        action: 'publish',
        onDone: () => _loadRepoStatus(repo),
      ),
    );
  }

  void _publishSelected() {
    final selected = _repos.where((r) => r.selected && !r.hasUpstream).toList();
    if (selected.isEmpty) return;
    _dismissSearchFocus();
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

  // ── Open in VSCode / Browser ──

  Future<void> _openPathInVscode(String path) async {
    final installed = await PlatformService.isVscodeInstalled();
    if (!installed) {
      if (!mounted) return;
      _dismissSearchFocus();
      AppDialog.show(
        context: context,
        builder: (ctx) => const VscodeInstallDialog(),
      );
      return;
    }
    try {
      if (Platform.isMacOS) {
        await Process.run(
          'open',
          ['-a', 'Visual Studio Code', path],
          runInShell: true,
        );
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'code', path], runInShell: true);
      } else {
        await Process.run('code', [path], runInShell: true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpenVscode)),
        );
      }
    }
  }

  Future<void> _openProjectInVscode() {
    _dismissSearchFocus();
    return _openPathInVscode(widget.projectPath);
  }

  Future<void> _openProjectInBrowser() async {
    if (!widget.hasNginx) return;
    _dismissSearchFocus();
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
    final url = 'https://${widget.nginxSubdomain}$dotSuffix';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url], runInShell: true);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url], runInShell: true);
      } else {
        await Process.run('xdg-open', [url], runInShell: true);
      }
    } catch (_) {}
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 1000
        ? AppDialog.widthXl
        : AppDialog.widthLg;

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
            onPressed: _openProjectInVscode,
            icon: const Icon(
              Icons.code,
              color: Colors.white,
              size: AppIconSize.md,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
              padding: EdgeInsets.zero,
            ),
            tooltip: context.l10n.openInVscode,
          ),
          const SizedBox(width: AppSpacing.sm),
          if (widget.hasNginx) ...[
            IconButton(
              onPressed: _openProjectInBrowser,
              icon: const Icon(
                Icons.language,
                color: Colors.white,
                size: AppIconSize.md,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.tertiary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
                padding: EdgeInsets.zero,
              ),
              tooltip: context.l10n.openInBrowser,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          IconButton(
            onPressed: () => _loadPinnedRepos(loadAll: true),
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
              size: AppIconSize.md,
            ),
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
    final filtered = _filteredRepoNames;
    final hasSearchResults = filtered.isNotEmpty;
    final safeHighlightedIndex = hasSearchResults
        ? _highlightedIndex.clamp(0, filtered.length - 1)
        : 0;
    final visibleItemCount = filtered.length < _kSearchMaxVisibleItems
        ? filtered.length
        : _kSearchMaxVisibleItems;
    final preferredPanelHeight = hasSearchResults
        ? visibleItemCount * _kSearchItemExtent
        : _kSearchItemExtent * 1.5;
    final maxResponsivePanelHeight = math.max(
      _kSearchItemExtent * 2,
      MediaQuery.of(context).size.height * 0.22,
    );
    final searchPanelHeight = math.min(
      preferredPanelHeight,
      maxResponsivePanelHeight,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = constraints.maxWidth < 860;
        final searchSection = TapRegion(
          onTapOutside: (_) {
            if (_isSearchOpen) {
              setState(() => _isSearchOpen = false);
            }
          },
          child: Column(
            children: [
              Focus(
                focusNode: _addRepoFocusNode,
                onFocusChange: (hasFocus) {
                  if (!mounted) return;
                  setState(() {
                    if (hasFocus) {
                      _isSearchOpen = true;
                      _highlightedIndex = 0;
                    }
                  });
                },
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent || !_isSearchOpen) {
                    return KeyEventResult.ignored;
                  }

                  final filtered = _filteredRepoNames;
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() => _isSearchOpen = false);
                    return KeyEventResult.handled;
                  }

                  if (filtered.isEmpty) return KeyEventResult.ignored;

                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _highlightedIndex = (_highlightedIndex + 1).clamp(
                        0,
                        filtered.length - 1,
                      );
                    });
                    _scrollHighlightedOptionIntoView();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _highlightedIndex = (_highlightedIndex - 1).clamp(
                        0,
                        filtered.length - 1,
                      );
                    });
                    _scrollHighlightedOptionIntoView();
                    return KeyEventResult.handled;
                  }

                  if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                    _handleRepoSelected(filtered[safeHighlightedIndex]);
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _addRepoController,
                    onTap: () {
                      setState(() => _isSearchOpen = true);
                    },
                    onChanged: (_) {
                      setState(() {
                        _isSearchOpen = true;
                        _highlightedIndex = 0;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: context.l10n.gitSearchRepo,
                      prefixIcon: const Icon(
                        Icons.add_circle_outline,
                        size: AppIconSize.md,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
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
                          IconButton(
                            onPressed: () {
                              setState(() => _isSearchOpen = !_isSearchOpen);
                              if (!_addRepoFocusNode.hasFocus) {
                                _addRepoFocusNode.requestFocus();
                              }
                            },
                            icon: Icon(
                              _isSearchOpen
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              size: AppIconSize.lg,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_isSearchOpen) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  constraints: BoxConstraints(maxHeight: searchPanelHeight),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dialogTheme.backgroundColor,
                    borderRadius: AppRadius.mediumBorderRadius,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No repositories found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : NotificationListener<ScrollEndNotification>(
                          onNotification: (_) {
                            _snapSearchListToItemBoundary();
                            return false;
                          },
                          child: ListView.builder(
                            controller: _searchListScrollController,
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemExtent: _kSearchItemExtent,
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final name = filtered[i];
                              final isHighlighted = i == safeHighlightedIndex;
                              return Material(
                                color: isHighlighted
                                    ? Colors.teal.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () => _handleRepoSelected(name),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.add_circle_outline,
                                          size: AppIconSize.md,
                                        ),
                                        const SizedBox(width: AppSpacing.md),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ],
          ),
        );
        final cloneButton = FilledButton.icon(
          onPressed: _cloneRepoToWorkspace,
          icon: const Icon(Icons.download, size: AppIconSize.md),
          label: const Text('Clone Repo'),
        );

        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchSection,
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerRight, child: cloneButton),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: searchSection),
            const SizedBox(width: AppSpacing.sm),
            cloneButton,
          ],
        );
      },
    );
  }

  void _scrollHighlightedOptionIntoView() {
    if (!_searchListScrollController.hasClients) return;
    final position = _searchListScrollController.position;
    final firstVisibleIndex = (position.pixels / _kSearchItemExtent).floor();
    final visibleItemCount = (position.viewportDimension / _kSearchItemExtent)
        .floor();

    double? targetOffset;
    if (_highlightedIndex < firstVisibleIndex) {
      targetOffset = _highlightedIndex * _kSearchItemExtent;
    } else if (_highlightedIndex >= firstVisibleIndex + visibleItemCount) {
      targetOffset =
          (_highlightedIndex - visibleItemCount + 1) * _kSearchItemExtent;
    }

    if (targetOffset == null) return;
    final clamped = targetOffset.clamp(0.0, position.maxScrollExtent);
    _searchListScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _snapSearchListToItemBoundary() {
    if (!_searchListScrollController.hasClients) return;
    final position = _searchListScrollController.position;
    final currentOffset = position.pixels;
    final snappedOffset =
        (currentOffset / _kSearchItemExtent).round() * _kSearchItemExtent;
    final clamped = snappedOffset.clamp(0.0, position.maxScrollExtent);
    if ((clamped - currentOffset).abs() < 0.5) return;
    _searchListScrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _openPublishDialog() {
    _dismissSearchFocus();
    AppDialog.show(
      context: context,
      builder: (ctx) => PublishModulesDialog(projectPath: widget.projectPath),
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
            _selectedCount == _repos.length ? Icons.deselect : Icons.select_all,
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
          icon: const Icon(GitActionIcons.pull, size: AppIconSize.md),
          label: Text(context.l10n.workspaceViewPullSelected),
        ),
        FilledButton.tonalIcon(
          onPressed: hasSelection ? _openCommitDialog : null,
          icon: const Icon(GitActionIcons.commit, size: AppIconSize.md),
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
            icon: const Icon(GitActionIcons.publish, size: AppIconSize.md),
            label: Text(context.l10n.workspaceViewPublishBranch),
          ),
        FilledButton.tonalIcon(
          onPressed: _openPublishDialog,
          icon: const Icon(GitActionIcons.publish, size: AppIconSize.md),
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
        onDoubleTap: () => _openPathInVscode(repo.path),
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
                        color: _branchColor(
                          repo.branch,
                        ).withValues(alpha: 0.15),
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
                  _statusBadge('${repo.changedFiles} \u2191', Colors.orange),
                if (repo.aheadCount > 0)
                  _statusBadge('${repo.aheadCount} \u2191', Colors.green),
                if (repo.behindCount > 0)
                  _statusBadge('${repo.behindCount} \u2193', Colors.cyan),
                // Per-repo actions
                const SizedBox(width: AppSpacing.md),
                _repoActionButton(
                  icon: GitActionIcons.pull,
                  tooltip: context.l10n.gitPull,
                  color: GitActionColors.pull,
                  onPressed: () => _pullSingle(repo),
                ),
                if (!repo.hasUpstream)
                  _repoActionButton(
                    icon: GitActionIcons.publish,
                    tooltip: context.l10n.gitBranchPublish(repo.branch),
                    color: GitActionColors.publish,
                    onPressed: () => _publishSingle(repo),
                  )
                else ...[
                  _repoActionButton(
                    icon: GitActionIcons.push,
                    tooltip: context.l10n.push,
                    color: GitActionColors.push,
                    onPressed: () => _pushSingle(repo),
                  ),
                  _repoActionButton(
                    icon: GitActionIcons.pr,
                    tooltip: context.l10n.gitBranchPR,
                    color: GitActionColors.pr,
                    onPressed: () => _createPrSingle(repo),
                  ),
                ],
              ],
              // Remove from workspace (always visible)
              _repoActionButton(
                icon: Icons.close,
                tooltip: context.l10n.removeFromList,
                color: GitActionColors.delete,
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
      icon: Icon(
        icon,
        size: AppIconSize.lg,
        color: onPressed != null ? color : null,
      ),
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}
