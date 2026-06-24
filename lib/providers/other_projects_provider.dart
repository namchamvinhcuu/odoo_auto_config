import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

class OtherProjectsState {
  final List<WorkspaceInfo> workspaces;
  final Map<String, String> branches;
  final Map<String, int> changedCount;
  final Map<String, int> behindCount;
  final Map<String, bool> fetchFailed;

  const OtherProjectsState({
    this.workspaces = const [],
    this.branches = const {},
    this.changedCount = const {},
    this.behindCount = const {},
    this.fetchFailed = const {},
  });

  OtherProjectsState copyWith({
    List<WorkspaceInfo>? workspaces,
    Map<String, String>? branches,
    Map<String, int>? changedCount,
    Map<String, int>? behindCount,
    Map<String, bool>? fetchFailed,
  }) {
    return OtherProjectsState(
      workspaces: workspaces ?? this.workspaces,
      branches: branches ?? this.branches,
      changedCount: changedCount ?? this.changedCount,
      behindCount: behindCount ?? this.behindCount,
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
    Future.microtask(() => _loadBranches(workspaces));
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
    _loadBranches(workspaces);
  }

  Future<void> _loadBranches(List<WorkspaceInfo> workspaces) async {
    for (final ws in workspaces) {
      await loadBranchStatus(ws.path);
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
    bool? fetchFailedValue;

    try {
      // Current branch
      final result = await Process.run(
        'git', ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: path, runInShell: true,
      );
      if (result.exitCode == 0) {
        final branch = (result.stdout as String).trim();
        if (branch.isNotEmpty) branchValue = branch;
      }

      // Changed files
      final statusResult = await Process.run(
        'git', ['status', '--porcelain'],
        workingDirectory: path, runInShell: true,
      );
      if (statusResult.exitCode == 0) {
        changedValue = (statusResult.stdout as String)
            .trimRight().split('\n').where((l) => l.isNotEmpty).length;
      }

      // Fetch quietly so @{upstream} reflects new remote commits.
      // Track failure so the UI can warn instead of silently showing 0 behind.
      final fetchResult = await Process.run(
        'git', ['fetch', '--quiet'],
        workingDirectory: path, runInShell: true,
      );
      fetchFailedValue = fetchResult.exitCode != 0;

      // Behind remote
      final behindResult = await Process.run(
        'git', ['rev-list', '--count', 'HEAD..@{upstream}'],
        workingDirectory: path, runInShell: true,
      );
      if (behindResult.exitCode == 0) {
        behindValue = int.tryParse((behindResult.stdout as String).trim()) ?? 0;
      }
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
