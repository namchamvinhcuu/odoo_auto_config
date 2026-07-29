import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

/// Number of repos to fetch git status for per parallel batch.
/// Bounds concurrent `git fetch` calls so many private-repo refreshes don't
/// trigger a credential-prompt storm or hit remote rate limits at once.
/// Mirrors the Odoo Workspace dashboard (`_kBatchSize` in odoo_workspace_dialog).
const _kBatchSize = 8;

class OtherProjectsState {
  final List<WorkspaceInfo> workspaces;
  final Map<String, String> branches;
  final Map<String, int> changedCount;
  final Map<String, int> behindCount;

  /// Local commits not yet pushed to the upstream, per repo path.
  /// Drives the "needs push" badge on the project cards.
  final Map<String, int> aheadCount;

  /// Whether the current branch has a usable upstream ref.
  /// False → the repo needs Publish, not Push, and [aheadCount] is 0.
  final Map<String, bool> hasUpstream;

  /// Commits that exist on no remote at all. Only meaningful where
  /// [hasUpstream] is false — a brand-new branch full of unpublished work.
  final Map<String, int> unpublishedCount;
  final Map<String, bool> fetchFailed;

  const OtherProjectsState({
    this.workspaces = const [],
    this.branches = const {},
    this.changedCount = const {},
    this.behindCount = const {},
    this.aheadCount = const {},
    this.hasUpstream = const {},
    this.unpublishedCount = const {},
    this.fetchFailed = const {},
  });

  OtherProjectsState copyWith({
    List<WorkspaceInfo>? workspaces,
    Map<String, String>? branches,
    Map<String, int>? changedCount,
    Map<String, int>? behindCount,
    Map<String, int>? aheadCount,
    Map<String, bool>? hasUpstream,
    Map<String, int>? unpublishedCount,
    Map<String, bool>? fetchFailed,
  }) {
    return OtherProjectsState(
      workspaces: workspaces ?? this.workspaces,
      branches: branches ?? this.branches,
      changedCount: changedCount ?? this.changedCount,
      behindCount: behindCount ?? this.behindCount,
      aheadCount: aheadCount ?? this.aheadCount,
      hasUpstream: hasUpstream ?? this.hasUpstream,
      unpublishedCount: unpublishedCount ?? this.unpublishedCount,
      fetchFailed: fetchFailed ?? this.fetchFailed,
    );
  }
}

class OtherProjectsNotifier extends AsyncNotifier<OtherProjectsState> {
  @override
  Future<OtherProjectsState> build() async {
    final workspaces = await _loadWorkspaces();
    final initialState = OtherProjectsState(workspaces: workspaces);
    // Schedule branch loading after state is set
    Future.microtask(() => loadBranches(workspaces));
    return initialState;
  }

  Future<List<WorkspaceInfo>> _loadWorkspaces() async {
    final json = await StorageService.loadWorkspaces();
    final workspaces = json.map((j) => WorkspaceInfo.fromJson(j)).toList();
    workspaces.sort((a, b) {
      if (a.favourite != b.favourite) return a.favourite ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return workspaces;
  }

  Future<void> reload() async {
    final workspaces = await _loadWorkspaces();
    state = AsyncData(OtherProjectsState(workspaces: workspaces));
    loadBranches(workspaces);
  }

  @visibleForTesting
  Future<void> loadBranches(List<WorkspaceInfo> workspaces) async {
    // Load repos in parallel batches instead of one-at-a-time. The per-repo
    // `git fetch` is network I/O, so sequential loading made refresh time grow
    // linearly with the number of projects. Batching caps concurrent fetches
    // (see _kBatchSize). Safe against the behind-count clobber race because
    // loadBranchStatus merges only its own path into the latest state.
    for (var i = 0; i < workspaces.length; i += _kBatchSize) {
      final batch = workspaces.skip(i).take(_kBatchSize);
      await Future.wait(batch.map((ws) => loadBranchStatus(ws.path)));
    }
  }

  Future<void> loadBranchStatus(String path) async {
    if (state.valueOrNull == null) return;
    if (!Directory(p.join(path, '.git')).existsSync()) return;

    // Compute values for THIS path only into locals. Don't snapshot the whole
    // state up-front and write it back wholesale — the git calls below each
    // await (yielding the event loop), so a concurrent loadBranchStatus for
    // another repo could finish in between and its stale snapshot would clobber
    // our fresh result (and vice-versa). We merge a single key at the end.
    String? branchValue;
    int? changedValue;
    int? behindValue;
    int? aheadValue;
    bool? hasUpstreamValue;
    int? unpublishedValue;
    bool? fetchFailedValue;

    try {
      // Local status (branch + changed files) via the shared helper — do NOT
      // inline the git commands here, they are measured identically elsewhere.
      final local = await GitBranchService.loadLocalStatus(path);
      if (local.branch.isNotEmpty) branchValue = local.branch;
      changedValue = local.changedFiles;

      // Fetch + re-measure divergence as ONE unit: measuring behind without
      // fetching first reads a stale remote-tracking ref and reports 0.
      // Every count is always assigned — a `0` from "no upstream" must overwrite
      // the previous branch's number, because leaving these null means "keep the
      // old map" in copyWith and the badge would stay stale after a switch.
      // fetchFailed is separate: upstream still exists then, rev-list exits 0.
      final fetched = await GitBranchService.fetchThenDiverge(path);
      fetchFailedValue = fetched.fetchFailed;
      behindValue = fetched.divergence.behind;
      aheadValue = fetched.divergence.ahead;
      hasUpstreamValue = fetched.divergence.hasUpstream;

      // Commits that exist on no remote at all. Only meaningful when the branch
      // has no upstream — that repo needs Publish, and `ahead` is 0 there.
      //
      // Two more cases must report 0, or the badge shows a number the user can do
      // nothing about and offers a Publish that can never succeed:
      //   - no `origin` at all → the count is the whole history, and publishing
      //     fails with "'origin' does not appear to be a git repository";
      //   - detached HEAD → there is no branch name to publish, and
      //     `push -u origin HEAD` is rejected as not a full refname.
      final publishable =
          !fetched.divergence.hasUpstream &&
          local.branch.isNotEmpty &&
          local.branch != 'HEAD' &&
          await GitBranchService.getRemoteUrl(path) != null;
      unpublishedValue = publishable
          ? await GitBranchService.loadUnpublishedCount(path)
          : 0;
    } catch (_) {}

    // Re-read the latest state and merge only THIS path's keys, so concurrent
    // updates for other repos are preserved instead of being overwritten.
    final latest = state.valueOrNull;
    if (latest == null) return;
    state = AsyncData(latest.copyWith(
      branches: branchValue == null
          ? null
          : {...latest.branches, path: branchValue},
      changedCount: changedValue == null
          ? null
          : {...latest.changedCount, path: changedValue},
      behindCount: behindValue == null
          ? null
          : {...latest.behindCount, path: behindValue},
      aheadCount: aheadValue == null
          ? null
          : {...latest.aheadCount, path: aheadValue},
      hasUpstream: hasUpstreamValue == null
          ? null
          : {...latest.hasUpstream, path: hasUpstreamValue},
      unpublishedCount: unpublishedValue == null
          ? null
          : {...latest.unpublishedCount, path: unpublishedValue},
      fetchFailed: fetchFailedValue == null
          ? null
          : {...latest.fetchFailed, path: fetchFailedValue},
    ));
  }

  Future<void> addWorkspace(WorkspaceInfo workspace) async {
    await StorageService.addWorkspace(workspace.toJson());
    await reload();
  }

  Future<void> updateWorkspace(WorkspaceInfo old, WorkspaceInfo updated) async {
    await StorageService.removeWorkspace(old.path);
    await StorageService.addWorkspace(updated.toJson());
    await reload();
  }

  Future<void> deleteWorkspace(WorkspaceInfo workspace,
      {bool deleteFiles = false}) async {
    if (workspace.hasNginx) {
      try {
        await NginxService.removeNginx(workspace.nginxSubdomain!);
      } catch (_) {}
    }
    if (deleteFiles) {
      try {
        final dir = Directory(workspace.path);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
    await StorageService.removeWorkspace(workspace.path);
    await reload();
  }

  Future<void> toggleFavourite(WorkspaceInfo workspace) async {
    final updated = workspace.copyWith(favourite: !workspace.favourite);
    await StorageService.removeWorkspace(workspace.path);
    await StorageService.addWorkspace(updated.toJson());
    await reload();
  }
}

final otherProjectsProvider =
    AsyncNotifierProvider<OtherProjectsNotifier, OtherProjectsState>(
        OtherProjectsNotifier.new);
