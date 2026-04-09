import 'dart:io';

/// Result of a git operation: success flag + combined output message.
typedef GitResult = ({bool success, String output});

/// Result of loading branches from a git repository.
typedef BranchesResult = ({
  List<String> local,
  List<String> remote,
  String current,
  int changedFiles,
  int behindRemote,
});

/// Result of cleaning stale branches (fetch --prune + find gone).
typedef StaleBranchesResult = ({List<String> staleBranches, String output});

/// Result of merging branches.
typedef MergeResult = ({
  bool success,
  String output,
  String currentBranch,
});

/// Stateless service for common git branch operations.
/// Handles only git commands — UI (dialogs, setState) stays in the caller.
class GitBranchService {
  /// Load local/remote branches, current branch status (changed files, behind count).
  static Future<BranchesResult> loadBranches(String workingDir) async {
    // Get branch list
    final result = await Process.run(
      'git',
      ['branch', '-a', '--format=%(refname)'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      return (
        local: <String>[],
        remote: <String>[],
        current: '',
        changedFiles: 0,
        behindRemote: 0,
      );
    }

    final localBranches = <String>{};
    final remoteBranches = <String>{};
    for (final ref in (result.stdout as String)
        .split('\n')
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)) {
      if (ref.contains('HEAD')) continue;
      if (ref.startsWith('refs/heads/')) {
        localBranches.add(ref.substring('refs/heads/'.length));
      } else if (ref.startsWith('refs/remotes/origin/')) {
        remoteBranches.add(ref.substring('refs/remotes/origin/'.length));
      }
    }

    // Detect current branch
    final headResult = await Process.run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    final current = headResult.exitCode == 0
        ? (headResult.stdout as String).trim()
        : '';

    // Changed files count
    int changed = 0;
    final statusResult = await Process.run(
      'git',
      ['status', '--porcelain'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (statusResult.exitCode == 0) {
      changed = (statusResult.stdout as String)
          .trimRight()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .length;
    }

    // Behind remote count
    int behind = 0;
    final behindResult = await Process.run(
      'git',
      ['rev-list', '--count', 'HEAD..@{upstream}'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (behindResult.exitCode == 0) {
      behind = int.tryParse((behindResult.stdout as String).trim()) ?? 0;
    }

    return (
      local: localBranches.toList(),
      remote: remoteBranches.toList(),
      current: current,
      changedFiles: changed,
      behindRemote: behind,
    );
  }

  /// Switch to an existing branch.
  static Future<GitResult> switchBranch(
    String workingDir,
    String branch,
  ) async {
    final result = await Process.run(
      'git',
      ['checkout', branch],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return (success: true, output: 'Switched to $branch');
    }
    return (success: false, output: (result.stderr as String).trim());
  }

  /// Create a new branch and switch to it.
  static Future<GitResult> createBranch(
    String workingDir,
    String name,
  ) async {
    final result = await Process.run(
      'git',
      ['checkout', '-b', name],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return (success: true, output: 'Created and switched to $name');
    }
    return (success: false, output: (result.stderr as String).trim());
  }

  /// Delete a local branch. Use [force] for `-D` (force delete unmerged).
  static Future<GitResult> deleteBranch(
    String workingDir,
    String name, {
    bool force = false,
  }) async {
    final result = await Process.run(
      'git',
      ['branch', force ? '-D' : '-d', name],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      final prefix = force ? 'Force deleted' : 'Deleted';
      return (success: true, output: '$prefix branch $name');
    }
    return (success: false, output: (result.stderr as String).trim());
  }

  /// Check if a delete failure is due to unmerged branch.
  static bool isNotFullyMergedError(String errorOutput) {
    return errorOutput.contains('not fully merged');
  }

  /// Publish a local branch to origin.
  /// Creates an empty commit to make the branch visible on GitHub.
  static Future<GitResult> publishBranch(
    String workingDir,
    String branch,
  ) async {
    // Create empty commit so the branch has its own commit on GitHub
    final commit = await Process.run(
      'git',
      ['commit', '--allow-empty', '-m', 'publish new branch: $branch'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (commit.exitCode != 0) {
      return (
        success: false,
        output: 'Commit failed: ${(commit.stderr as String).trim()}',
      );
    }

    final result = await Process.run(
      'git',
      ['push', '-u', 'origin', branch],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode == 0) {
      return (success: true, output: 'Published $branch to origin');
    }
    return (
      success: false,
      output: 'Push failed: ${(result.stderr as String).trim()}',
    );
  }

  /// Fetch --prune and find local branches whose upstream is gone.
  /// Returns the list of stale branch names (excludes [currentBranch]).
  static Future<StaleBranchesResult> cleanStaleBranches(
    String workingDir, {
    String? currentBranch,
  }) async {
    // Fetch + prune remote refs
    await Process.run(
      'git',
      ['fetch', '--prune'],
      workingDirectory: workingDir,
      runInShell: true,
    );

    // Find local branches whose upstream is gone
    final result = await Process.run(
      'git',
      ['branch', '-vv'],
      workingDirectory: workingDir,
      runInShell: true,
    );

    final gone = <String>[];
    for (final line in (result.stdout as String).split('\n')) {
      if (line.contains(': gone]')) {
        final branch = line
            .trim()
            .split(RegExp(r'\s+'))
            .first
            .replaceFirst('*', '')
            .trim();
        if (branch.isNotEmpty && branch != currentBranch) {
          gone.add(branch);
        }
      }
    }

    if (gone.isEmpty) {
      return (
        staleBranches: <String>[],
        output: 'All local branches are up to date with remote',
      );
    }
    return (staleBranches: gone, output: '');
  }

  /// Delete multiple branches (force). Returns deleted and failed lists.
  static Future<({List<String> deleted, List<String> failed})>
      deleteBranches(
    String workingDir,
    List<String> branches,
  ) async {
    final deleted = <String>[];
    final failed = <String>[];
    for (final branch in branches) {
      final del = await Process.run(
        'git',
        ['branch', '-D', branch],
        workingDirectory: workingDir,
        runInShell: true,
      );
      if (del.exitCode == 0) {
        deleted.add(branch);
      } else {
        failed.add(branch);
      }
    }
    return (deleted: deleted, failed: failed);
  }

  /// Merge a branch into the current branch, then push.
  static Future<MergeResult> mergeIntoCurrent(
    String workingDir,
    String sourceBranch,
    String currentBranch,
  ) async {
    final result = await Process.run(
      'git',
      ['merge', sourceBranch],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      final stdout = (result.stdout as String).trim();
      return (
        success: false,
        output: stderr.isNotEmpty ? stderr : stdout,
        currentBranch: currentBranch,
      );
    }

    // Push after merge
    final push = await Process.run(
      'git',
      ['push'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (push.exitCode == 0) {
      return (
        success: true,
        output: 'Merged $sourceBranch into $currentBranch and pushed',
        currentBranch: currentBranch,
      );
    }
    return (
      success: false,
      output:
          'Merged $sourceBranch into $currentBranch (push failed: ${(push.stderr as String).trim()})',
      currentBranch: currentBranch,
    );
  }

  /// Merge current branch into a target branch:
  /// checkout target → merge current → push → checkout back.
  static Future<MergeResult> mergeIntoTarget(
    String workingDir,
    String currentBranch,
    String targetBranch,
  ) async {
    // Checkout target
    var result = await Process.run(
      'git',
      ['checkout', targetBranch],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      return (
        success: false,
        output:
            'Checkout $targetBranch failed: ${(result.stderr as String).trim()}',
        currentBranch: currentBranch,
      );
    }

    // Merge current into target
    result = await Process.run(
      'git',
      ['merge', currentBranch],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      // Merge failed — stay on target so user can resolve
      final stderr = (result.stderr as String).trim();
      final stdout = (result.stdout as String).trim();
      return (
        success: false,
        output: 'Merge failed: ${stderr.isNotEmpty ? stderr : stdout}',
        currentBranch: targetBranch, // now on target branch
      );
    }

    // Push target
    final push = await Process.run(
      'git',
      ['push'],
      workingDirectory: workingDir,
      runInShell: true,
    );

    // Checkout back to original branch
    await Process.run(
      'git',
      ['checkout', currentBranch],
      workingDirectory: workingDir,
      runInShell: true,
    );

    if (push.exitCode == 0) {
      return (
        success: true,
        output: 'Merged $currentBranch into $targetBranch and pushed',
        currentBranch: currentBranch,
      );
    }
    return (
      success: false,
      output:
          'Merged $currentBranch into $targetBranch (push failed: ${(push.stderr as String).trim()})',
      currentBranch: currentBranch,
    );
  }

  /// Get the HTTPS URL for the remote origin of a git repository.
  /// Returns `null` if no remote is configured or parsing fails.
  static Future<String?> getRemoteUrl(String workingDir) async {
    final result = await Process.run(
      'git',
      ['remote', 'get-url', 'origin'],
      workingDirectory: workingDir,
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    var url = (result.stdout as String).trim();
    if (url.isEmpty) return null;
    // Convert SSH to HTTPS: git@github.com:org/repo.git → https://github.com/org/repo
    if (url.startsWith('git@')) {
      url = url.replaceFirst('git@', 'https://').replaceFirst(':', '/');
    }
    // Remove trailing .git
    if (url.endsWith('.git')) {
      url = url.substring(0, url.length - 4);
    }
    return url;
  }

  /// Open a URL in the default browser (cross-platform).
  static Future<void> openInBrowser(String url) async {
    final cmd = Platform.isMacOS
        ? 'open'
        : Platform.isWindows
            ? 'start'
            : 'xdg-open';
    await Process.run(cmd, [url], runInShell: true);
  }
}
