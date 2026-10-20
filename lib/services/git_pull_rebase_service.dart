import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:odoo_auto_config/services/git_branch_service.dart';
import 'package:odoo_auto_config/services/git_process.dart';

/// How a [GitPullRebaseService.pullRebase] run ended.
enum PullRebaseOutcome {
  /// Rebased cleanly.
  success,

  /// Rebased, but re-applying the autostash conflicted (git still exits 0):
  /// files are left unmerged and the changes are also kept in `git stash list`.
  /// Committing now with `git add -A` would commit the conflict markers.
  stashConflict,

  /// Stopped part-way (usually a conflict) and rolled back with
  /// `git rebase --abort`: the repo is exactly as it was before.
  aborted,

  /// Stopped part-way and `git rebase --abort` failed too (stale `index.lock`,
  /// a Windows file lock): the repo is still mid-rebase.
  stuckInRebase,

  /// Not started: a rebase, `git am` or merge was already in progress. That
  /// operation is the user's — we never abort it.
  refused,

  /// Failed before anything was rebased (network, auth, no upstream…).
  failed,
}

typedef PullRebaseResult = ({PullRebaseOutcome outcome, int exitCode});

/// Recovers a branch that has diverged from its upstream (local commits AND new
/// remote commits), where a plain `git pull` refuses to fast-forward and
/// `git push` is rejected as non-fast-forward.
///
/// Stateless; UI (buttons, log lines) stays in the dialogs.
class GitPullRebaseService {
  /// True while a rebase is stopped in [workingDir] (`rebase-merge`, or
  /// `rebase-apply` which also covers `git am`).
  static Future<bool> isRebaseInProgress(String workingDir) async =>
      await _gitPathExists(workingDir, 'rebase-merge') ||
      await _gitPathExists(workingDir, 'rebase-apply');

  /// True when the repo is in the middle of something we must not touch: a
  /// stopped rebase/`am`, a merge, or unresolved conflicts.
  static Future<bool> _isBusy(String workingDir) async =>
      await isRebaseInProgress(workingDir) ||
      await _gitPathExists(workingDir, 'MERGE_HEAD') ||
      await _hasUnmergedFiles(workingDir);

  static Future<bool> _gitPathExists(String workingDir, String name) async {
    final result = await runGit(
      ['rev-parse', '--git-path', name],
      workingDir: workingDir,
    );
    if (result.exitCode != 0) return false;
    // `--git-path` may answer relative to the working dir.
    final path = p.join(workingDir, (result.stdout as String).trim());
    return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
  }

  static Future<bool> _hasUnmergedFiles(String workingDir) async {
    // `:/` = whole repo: plain `ls-files -u` only lists the current directory,
    // so a subdir working dir would miss every conflict elsewhere.
    final result = await runGit(
      ['ls-files', '-u', '--', ':/'],
      workingDir: workingDir,
    );
    return result.exitCode == 0 &&
        (result.stdout as String).trim().isNotEmpty;
  }

  /// Whether offering "Pull (rebase)" makes sense right now: the branch is both
  /// ahead of and behind its upstream, and the repo is not mid-operation.
  ///
  /// Reads the remote-tracking ref as is — call it right after a `git pull`
  /// (which fetched) or after [GitBranchService.fetchThenDiverge].
  static Future<bool> canOfferPullRebase(String workingDir) async {
    final d = await GitBranchService.loadUpstreamDivergence(workingDir);
    if (!d.hasUpstream || d.ahead == 0 || d.behind == 0) return false;
    return !await _isBusy(workingDir);
  }

  /// Push was rejected: refresh the remote-tracking ref, then report whether the
  /// remote has commits we lack, which a pull --rebase can fix.
  static Future<bool> canOfferPullRebaseAfterPushRejected(
    String workingDir,
  ) async {
    final fetched = await GitBranchService.fetchThenDiverge(workingDir);
    final d = fetched.divergence;
    if (fetched.fetchFailed || !d.hasUpstream || d.behind == 0) return false;
    return !await _isBusy(workingDir);
  }

  /// Run `git pull --rebase --autostash`, streaming every output line to
  /// [onOutput].
  ///
  /// Re-checks that the repo is not mid-operation first: the button that calls
  /// this can sit on screen while the user starts a rebase in a terminal, and
  /// aborting THAT rebase would throw away their staged resolution. Past this
  /// check, any rebase left stopped belongs to this run, so it is rolled back
  /// with `git rebase --abort` (which also re-applies the autostash).
  static Future<PullRebaseResult> pullRebase(
    String workingDir, {
    required void Function(String line) onOutput,
  }) async {
    if (await _isBusy(workingDir)) {
      return (outcome: PullRebaseOutcome.refused, exitCode: 0);
    }
    final process = await startGit(
      ['pull', '--rebase', '--autostash'],
      workingDir: workingDir,
    );
    // allowMalformed: a decode error here would skip the abort below and leave
    // a conflicted run mid-rebase.
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutDone = process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(onOutput)
        .asFuture();
    final stderrDone = process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(onOutput)
        .asFuture();
    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (exitCode == 0) {
      // Exit 0 does not mean clean: an autostash that conflicts on re-apply
      // still exits 0. Check the index, not git's (localized) text.
      final outcome = await _hasUnmergedFiles(workingDir)
          ? PullRebaseOutcome.stashConflict
          : PullRebaseOutcome.success;
      return (outcome: outcome, exitCode: 0);
    }

    if (!await isRebaseInProgress(workingDir)) {
      return (outcome: PullRebaseOutcome.failed, exitCode: exitCode);
    }
    final abort = await runGit(['rebase', '--abort'], workingDir: workingDir);
    final abortOutput =
        '${abort.stdout as String}\n${abort.stderr as String}'.trim();
    if (abortOutput.isNotEmpty) abortOutput.split('\n').forEach(onOutput);
    return (
      outcome: abort.exitCode == 0
          ? PullRebaseOutcome.aborted
          : PullRebaseOutcome.stuckInRebase,
      exitCode: exitCode,
    );
  }
}
