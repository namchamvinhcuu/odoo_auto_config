import 'dart:io';

/// Environment applied to every git invocation.
///
/// `GIT_TERMINAL_PROMPT=0` makes git fail fast instead of blocking on an
/// interactive credential prompt. Dialogs that run git disable their close button
/// while the process is alive, so a git process waiting on stdin leaves the
/// dialog impossible to dismiss — the user has to kill the app.
///
/// Credential helpers and the macOS keychain keep working: this disables only the
/// *terminal* prompt, and the parent environment (PATH, HOME, SSH_AUTH_SOCK) is
/// still inherited because [Process.run] includes it by default.
///
/// Caveat: it does not cover a passphrase prompt coming from `ssh` itself.
///
/// Documented exception: the `git --version` probes in `GitService` stay outside
/// these helpers. They run before we know whether git exists or where it lives,
/// touch no repo and no network, and so cannot prompt for anything.
const Map<String, String> kGitEnvironment = {'GIT_TERMINAL_PROMPT': '0'};

/// Run a git command to completion.
///
/// Use this instead of calling [Process.run] with git directly. It is the one
/// place that pins two things every git call needs: `runInShell` (cross-platform
/// process safety) and [kGitEnvironment]. Adding a raw `Process.run('git', ...)`
/// re-opens the hanging-dialog bug for that call site only, which is exactly the
/// kind of drift that is hard to spot in review.
///
/// Pass [executable] when the git binary is a user-configured path rather than
/// whatever `git` resolves to on PATH (see `GitService.gitPath`). Grepping for the
/// literal `'git'` will not find those call sites — that is how two of them were
/// missed the first time.
Future<ProcessResult> runGit(
  List<String> args, {
  required String workingDir,
  String executable = 'git',
}) {
  return Process.run(
    executable,
    args,
    workingDirectory: workingDir,
    runInShell: true,
    environment: kGitEnvironment,
  );
}

/// Start a git command for streaming stdout/stderr. Same contract as [runGit].
Future<Process> startGit(
  List<String> args, {
  required String workingDir,
  String executable = 'git',
}) {
  return Process.start(
    executable,
    args,
    workingDirectory: workingDir,
    runInShell: true,
    environment: kGitEnvironment,
  );
}

/// Start a git command that is NOT scoped to an existing repo — `clone`, where the
/// destination is already an absolute path — and so has no working dir to run in.
///
/// Separate from [startGit] on purpose: making `workingDir` optional there would
/// let a repo-scoped command silently run in the app's own directory, against the
/// wrong repo. Reach for this only when there is genuinely no repo yet.
Future<Process> startGitInCurrentDir(
  List<String> args, {
  String executable = 'git',
}) {
  return Process.start(
    executable,
    args,
    runInShell: true,
    environment: kGitEnvironment,
  );
}
