import 'dart:convert';
import 'dart:io';
import 'package:odoo_auto_config/services/git_process.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

/// Result of a git operation: success flag + combined output message.
typedef GitResult = ({bool success, String output});

/// Result of loading branches from a git repository.
typedef BranchesResult = ({
  List<String> local,
  List<String> remote,
  String current,
  int changedFiles,
  int behindRemote,
  int aheadRemote,
  bool hasUpstream,
});

/// Divergence of the current branch against its upstream.
///
/// [hasUpstream] false means there is no usable upstream ref — none configured,
/// detached HEAD, or the ref was pruned away. In that case both counts are `0`,
/// which is a real value and not "unknown".
typedef UpstreamDivergence = ({int ahead, int behind, bool hasUpstream});

/// Local-only git status of a working dir: no network, fast.
typedef LocalGitStatus = ({String branch, int changedFiles});

/// Result of refreshing the remote-tracking ref and re-measuring divergence.
///
/// [fetchFailed] is reported separately from the counts on purpose: a failed
/// fetch leaves the remote-tracking ref stale, so `behind: 0` means "nothing new
/// that we know of", not "up to date". The UI must warn instead of showing a
/// confident zero.
typedef FetchedDivergence = ({bool fetchFailed, UpstreamDivergence divergence});

/// Result of cleaning stale branches (fetch --prune + find gone).
typedef StaleBranchesResult = ({List<String> staleBranches, String output});

/// Result of merging branches.
typedef MergeResult = ({bool success, String output, String currentBranch});

/// Stateless service for common git branch operations.
/// Handles only git commands — UI (dialogs, setState) stays in the caller.
class GitBranchService {
  /// Ensure origin fetches all remote branches, even for repos cloned with
  /// `--single-branch`.
  static Future<void> ensureOriginFetchesAllBranches(String workingDir) async {
    final currentRefspec = await runGit(
      ['config', '--get-all', 'remote.origin.fetch'],
      workingDir: workingDir,
    );
    if (currentRefspec.exitCode != 0) return;

    const fullRefspec = '+refs/heads/*:refs/remotes/origin/*';
    final refspecs = (currentRefspec.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (refspecs.length == 1 && refspecs.first == fullRefspec) {
      return;
    }

    await runGit(
      ['config', '--unset-all', 'remote.origin.fetch'],
      workingDir: workingDir,
    );
    await runGit(
      ['config', '--add', 'remote.origin.fetch', fullRefspec],
      workingDir: workingDir,
    );
  }

  /// Expand fetch refspec if needed, then fetch + prune remote branches.
  static Future<void> fetchAllBranches(String workingDir) async {
    await ensureOriginFetchesAllBranches(workingDir);
    await runGit(
      ['fetch', '--prune', '--quiet', 'origin'],
      workingDir: workingDir,
    );
  }

  /// Single source of truth for the local-only part of git status.
  ///
  /// Counting changed files used to be written out three times with three
  /// slightly different line-splitting expressions; only two of them were under
  /// test. Route every caller through here instead of running the commands again.
  ///
  /// Returns an empty branch name if HEAD cannot be resolved (empty repo), and
  /// `0` changed files if `status` fails — never a leftover from an earlier read.
  static Future<LocalGitStatus> loadLocalStatus(String workingDir) async {
    final branchResult = await runGit(
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDir: workingDir,
    );
    final branch = branchResult.exitCode == 0
        ? (branchResult.stdout as String).trim()
        : '';

    final statusResult = await runGit(
      ['status', '--porcelain'],
      workingDir: workingDir,
    );
    // LineSplitter handles both \n and Windows \r\n.
    final changedFiles = statusResult.exitCode == 0
        ? LineSplitter.split((statusResult.stdout as String).trimRight())
              .where((l) => l.isNotEmpty)
              .length
        : 0;

    return (branch: branch, changedFiles: changedFiles);
  }

  /// Refresh the remote-tracking ref, then measure divergence against it.
  ///
  /// These two steps are one unit on purpose. Measuring `behind` without
  /// fetching first reads a stale remote-tracking ref and silently reports `0`;
  /// that bug shipped once already. Keeping the fetch and the re-measure inside
  /// one call makes it impossible to drop the second half by accident.
  static Future<FetchedDivergence> fetchThenDiverge(String workingDir) async {
    final fetchResult = await runGit(
      ['fetch', '--quiet'],
      workingDir: workingDir,
    );
    final divergence = await loadUpstreamDivergence(workingDir);
    return (
      fetchFailed: fetchResult.exitCode != 0,
      divergence: divergence,
    );
  }

  /// Count commits on HEAD that exist on no remote at all.
  ///
  /// Needed when the branch has no upstream: [loadUpstreamDivergence] reports
  /// `ahead: 0` there (correctly — there is nothing to be ahead *of*), which
  /// would otherwise hide a brand-new branch full of unpublished work. Such a
  /// branch needs Publish, not Push.
  ///
  /// Unlike `@{upstream}` this never fails on a valid repo: `--not --remotes`
  /// resolves to "no remotes" rather than a fatal error.
  static Future<int> loadUnpublishedCount(String workingDir) async {
    final result = await runGit(
      ['rev-list', '--count', 'HEAD', '--not', '--remotes'],
      workingDir: workingDir,
    );
    if (result.exitCode != 0) return 0;
    return int.tryParse((result.stdout as String).trim()) ?? 0;
  }

  /// Single source of truth for ahead/behind counts vs the upstream.
  ///
  /// Every git-status code path MUST go through this instead of running
  /// `rev-list` itself. Three separate implementations used to exist and drifted
  /// apart three times: one gained an `ahead` count the others lacked, and two
  /// of them left the previous read's number in place when `rev-list` failed, so
  /// a stale badge survived a branch switch.
  ///
  /// Callers MUST assign all three returned fields unconditionally — never skip
  /// the assignment on `hasUpstream == false`, or the leftover-value bug returns.
  ///
  /// This applies to a value that was actually returned. If the call itself
  /// throws (git missing from PATH, working dir gone), a caller may deliberately
  /// keep its previous snapshot instead: `other_projects_provider` does that, and
  /// it is correct there because *every* field stays stale together — including
  /// the branch name — so no branch/count mismatch can appear on screen. Do not
  /// "fix" that catch into writing zeros for this field alone.
  static Future<UpstreamDivergence> loadUpstreamDivergence(
    String workingDir,
  ) async {
    final aheadResult = await runGit(
      ['rev-list', '--count', '@{upstream}..HEAD'],
      workingDir: workingDir,
    );
    // Both counts resolve `@{upstream}`, so they fail together. Bailing out here
    // guarantees the pair can never be half-updated.
    if (aheadResult.exitCode != 0) {
      return (ahead: 0, behind: 0, hasUpstream: false);
    }
    final ahead = int.tryParse((aheadResult.stdout as String).trim()) ?? 0;

    final behindResult = await runGit(
      ['rev-list', '--count', 'HEAD..@{upstream}'],
      workingDir: workingDir,
    );
    final behind = behindResult.exitCode == 0
        ? (int.tryParse((behindResult.stdout as String).trim()) ?? 0)
        : 0;

    return (ahead: ahead, behind: behind, hasUpstream: true);
  }

  /// Load local/remote branches, current branch status (changed files,
  /// behind/ahead count vs upstream).
  static Future<BranchesResult> loadBranches(String workingDir) async {
    // Get branch list
    final result = await runGit(
      ['branch', '-a', '--format=%(refname)'],
      workingDir: workingDir,
    );
    if (result.exitCode != 0) {
      return (
        local: <String>[],
        remote: <String>[],
        current: '',
        changedFiles: 0,
        behindRemote: 0,
        aheadRemote: 0,
        hasUpstream: false,
      );
    }

    final localBranches = <String>{};
    final remoteBranches = <String>{};
    for (final ref
        in (result.stdout as String)
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

    // Current branch + changed files via the shared local-status helper.
    final local = await loadLocalStatus(workingDir);
    final current = local.branch;
    final changed = local.changedFiles;

    final divergence = await loadUpstreamDivergence(workingDir);

    return (
      local: localBranches.toList(),
      remote: remoteBranches.toList(),
      current: current,
      changedFiles: changed,
      behindRemote: divergence.behind,
      aheadRemote: divergence.ahead,
      hasUpstream: divergence.hasUpstream,
    );
  }

  /// Push the current branch to its already-configured upstream.
  ///
  /// Only valid when the branch has an upstream (see [BranchesResult.hasUpstream]);
  /// for a brand-new local branch use [publishBranch] instead.
  static Future<GitResult> pushCurrentBranch(String workingDir) async {
    final result = await runGit(['push'], workingDir: workingDir);
    // git push writes progress + rejection reasons to stderr, so surface both
    // streams instead of swallowing the failure detail.
    final stdoutText = (result.stdout as String).trim();
    final stderrText = (result.stderr as String).trim();
    final output = [
      stdoutText,
      stderrText,
    ].where((s) => s.isNotEmpty).join('\n');
    if (result.exitCode == 0) {
      return (
        success: true,
        output: output.isEmpty ? 'Pushed to origin' : output,
      );
    }
    return (
      success: false,
      output: output.isEmpty ? 'Push failed' : 'Push failed: $output',
    );
  }

  /// Switch to an existing branch.
  static Future<GitResult> switchBranch(
    String workingDir,
    String branch,
  ) async {
    final result = await runGit(['checkout', branch], workingDir: workingDir);
    if (result.exitCode == 0) {
      return (success: true, output: 'Switched to $branch');
    }
    return (success: false, output: (result.stderr as String).trim());
  }

  /// Create a new branch and switch to it.
  /// If [baseBranch] is provided, creates from that branch instead of HEAD.
  static Future<GitResult> createBranch(
    String workingDir,
    String name, {
    String? baseBranch,
  }) async {
    final result = await runGit(
      ['checkout', '-b', name, if (baseBranch != null) baseBranch],
      workingDir: workingDir,
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
    final result = await runGit(
      ['branch', force ? '-D' : '-d', name],
      workingDir: workingDir,
    );
    if (result.exitCode == 0) {
      final prefix = force ? 'Force deleted' : 'Deleted';
      return (success: true, output: '$prefix branch $name');
    }
    return (success: false, output: (result.stderr as String).trim());
  }

  /// Delete a remote branch (`git push origin --delete <name>`).
  static Future<GitResult> deleteRemoteBranch(
    String workingDir,
    String name,
  ) async {
    final result = await runGit(
      ['push', 'origin', '--delete', name],
      workingDir: workingDir,
    );
    if (result.exitCode == 0) {
      return (success: true, output: 'Deleted remote branch $name');
    }
    return (success: false, output: (result.stderr as String).trim());
  }

  /// Check if a branch has an open (unmerged) PR on GitHub.
  /// Returns true if there is at least one open PR with this branch as head.
  static Future<bool> hasOpenPR(String workingDir, String branch) async {
    // Only pass GH_TOKEN as fallback when gh is not natively authenticated
    Map<String, String>? env;
    final token = await StorageService.getDefaultGitToken();
    if (token != null) {
      final authCheck = await PlatformService.runGh(['auth', 'status']);
      if (authCheck.exitCode != 0) {
        env = {'GH_TOKEN': token};
      }
    }
    final result = await PlatformService.runGh(
      [
        'pr',
        'list',
        '--head',
        branch,
        '--state',
        'open',
        '--json',
        'number',
        '--limit',
        '1',
      ],
      workingDirectory: workingDir,
      environment: env,
    );
    if (result.exitCode != 0) return false;
    final output = (result.stdout as String).trim();
    // gh returns "[]" when no PRs found
    return output.isNotEmpty && output != '[]';
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
    final commit = await runGit(
      ['commit', '--allow-empty', '-m', 'publish new branch: $branch'],
      workingDir: workingDir,
    );
    if (commit.exitCode != 0) {
      return (
        success: false,
        output: 'Commit failed: ${(commit.stderr as String).trim()}',
      );
    }

    final result = await runGit(
      ['push', '-u', 'origin', branch],
      workingDir: workingDir,
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
    await fetchAllBranches(workingDir);

    // Find local branches whose upstream is gone
    final result = await runGit(['branch', '-vv'], workingDir: workingDir);

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
  static Future<({List<String> deleted, List<String> failed})> deleteBranches(
    String workingDir,
    List<String> branches,
  ) async {
    final deleted = <String>[];
    final failed = <String>[];
    for (final branch in branches) {
      final del = await runGit(
        ['branch', '-D', branch],
        workingDir: workingDir,
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
    final result = await runGit(
      ['merge', sourceBranch],
      workingDir: workingDir,
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
    final push = await runGit(['push'], workingDir: workingDir);
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
    var result = await runGit(
      ['checkout', targetBranch],
      workingDir: workingDir,
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
    result = await runGit(['merge', currentBranch], workingDir: workingDir);
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
    final push = await runGit(['push'], workingDir: workingDir);

    // Checkout back to original branch
    await runGit(['checkout', currentBranch], workingDir: workingDir);

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
    final result = await runGit(
      ['remote', 'get-url', 'origin'],
      workingDir: workingDir,
    );
    if (result.exitCode != 0) return null;
    var url = (result.stdout as String).trim();
    if (url.isEmpty) return null;
    // Convert SSH to HTTPS: git@github.com:org/repo.git → https://github.com/org/repo
    if (url.startsWith('git@')) {
      url = url.replaceFirstMapped(
        RegExp(r'git@([^:]+):(.+)'),
        (m) => 'https://${m[1]}/${m[2]}',
      );
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
