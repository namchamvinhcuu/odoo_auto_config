import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'command_runner.dart';
import 'platform_service.dart';

class GitService {
  /// Cached across the whole process — resolving [gitPath] runs `--version`
  /// once per candidate, and every `runGit`/`startGit` call in
  /// [GitBranchService] resolves it, so a fresh probe per call would double
  /// the number of processes spawned per git operation.
  static String? _cachedGitPath;

  /// A candidate path "existing" is not enough to pick it — on this exact
  /// machine `/usr/bin/git` (the Xcode CLT stub) exists but fails every call
  /// with "You have not agreed to the Xcode license agreements" (exit 69)
  /// until `sudo xcodebuild -license` runs. A GUI-launched app (double-click
  /// the .dmg, no `~/.zshrc`) only has the OS default PATH — which resolves
  /// bare `'git'` to that broken stub even though a working Homebrew git
  /// sits at `/opt/homebrew/bin/git` and is what the same command resolves to
  /// from a Terminal-launched dev build. Verifying with a real `--version`
  /// run (not just `File.exists`) is what lets this loop skip the broken
  /// candidate and fall through to one that actually runs.
  static Future<bool> _canRunAsGit(String gitCandidate) async {
    try {
      final result = await Process.run(
        gitCandidate,
        ['--version'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// First candidate that both exists AND actually runs, extracted out of
  /// [gitPath] so tests can exercise the "exists but broken" skip logic (the
  /// Xcode-stub scenario documented on [_canRunAsGit]) with disposable
  /// fixture paths instead of the hardcoded macOS ones — those differ per
  /// machine and can't be reliably broken on an arbitrary test runner.
  static Future<String?> _firstWorkingCandidate(
    List<String> candidates,
  ) async {
    for (final path in candidates) {
      if (await File(path).exists() && await _canRunAsGit(path)) {
        return path;
      }
    }
    return null;
  }

  /// Test-only seam for [_firstWorkingCandidate]. Production code never
  /// calls this directly (it goes through [gitPath]) — it exists purely so
  /// tests can verify the skip-broken-candidate loop without depending on
  /// what git binaries happen to exist on the machine running the test.
  @visibleForTesting
  static Future<String?> debugFirstWorkingCandidate(
    List<String> candidates,
  ) =>
      _firstWorkingCandidate(candidates);

  /// Test-only seam to inject/reset the process-wide cache. Production code
  /// never calls this. Tests use it to (1) force [gitPath] — and therefore
  /// `runGit`/`startGit`/`startGitInCurrentDir` when they don't receive an
  /// explicit `executable` — to resolve to a fixture path regardless of what
  /// is actually installed, and (2) reset the cache in `tearDown` so one
  /// test's override can't leak into the next.
  @visibleForTesting
  static void debugOverrideCachedGitPath(String? path) {
    _cachedGitPath = path;
  }

  /// Test-only read of the raw cache slot — lets tests assert the cache was
  /// actually reset to `null` (not just "some other non-null value") without
  /// forcing a real re-resolve through [gitPath] to observe it indirectly.
  @visibleForTesting
  static String? get debugCachedGitPath => _cachedGitPath;

  /// Test-only seam to replace the real installer spawn used by [install].
  /// Production code always leaves this `null` (falls back to
  /// [_runInstaller]); tests set it so they can verify [install]'s
  /// cache-invalidation contract without actually running `xcode-select
  /// --install` / `winget` / `pkexec` on the machine executing the test.
  @visibleForTesting
  static Future<int> Function(void Function(String line) onOutput)?
      debugInstallerOverride;

  static Future<String> get gitPath async {
    if (_cachedGitPath != null) return _cachedGitPath!;
    if (PlatformService.isMacOS) {
      final found = await _firstWorkingCandidate([
        '/usr/bin/git',
        '/usr/local/bin/git',
        '/opt/homebrew/bin/git',
      ]);
      if (found != null) return _cachedGitPath = found;
    }
    return _cachedGitPath = 'git';
  }

  static Future<bool> isInstalled() async {
    final git = await gitPath;
    return _canRunAsGit(git);
  }

  static Future<String?> getVersion() async {
    try {
      final git = await gitPath;
      final result = await Process.run(git, ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final match =
            RegExp(r'git version (\S+)').firstMatch(result.stdout.toString());
        return match?.group(1);
      }
    } catch (_) {}
    return null;
  }

  static ({String executable, List<String> args, String description})
      installCommand() {
    if (PlatformService.isWindows) {
      return (
        executable: 'winget',
        args: [
          'install',
          '--id',
          'Git.Git',
          '-e',
          '--source',
          'winget',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install --id Git.Git',
      );
    } else if (PlatformService.isMacOS) {
      return (
        executable: 'xcode-select',
        args: ['--install'],
        description: 'xcode-select --install',
      );
    } else if (PlatformService.isDnf) {
      return (
        executable: 'pkexec',
        args: ['dnf', 'install', '-y', 'git'],
        description: 'pkexec dnf install -y git',
      );
    } else {
      return (
        executable: 'pkexec',
        args: ['apt', 'install', '-y', 'git'],
        description: 'pkexec apt install -y git',
      );
    }
  }

  /// Runs the platform installer, then invalidates [_cachedGitPath] regardless
  /// of outcome — `_ensureGit()`-style callers (`clone_repository_dialog.dart`,
  /// `clone_odoo_dialog.dart`) call `isInstalled()` (which caches "not found")
  /// BEFORE this, then read `gitPath` right after a successful install expecting
  /// the newly-installed binary. A stale cache from before the install ran would
  /// keep resolving to the old (missing/broken) result for the rest of the
  /// process. The macOS branch below only opens the installer dialog and
  /// returns before anything is actually installed, so it needs the same
  /// invalidation as the Windows/Linux branch that waits for a real exit code.
  static Future<int> install(void Function(String line) onOutput) async {
    final exitCode = await (debugInstallerOverride ?? _runInstaller)(onOutput);
    _cachedGitPath = null;
    return exitCode;
  }

  static Future<int> _runInstaller(void Function(String line) onOutput) async {
    final cmd = installCommand();
    onOutput('[+] Running: ${cmd.description}');
    onOutput('');

    if (PlatformService.isMacOS) {
      // xcode-select --install opens a system dialog
      try {
        await Process.run(cmd.executable, cmd.args, runInShell: true);
        onOutput('[+] Xcode Command Line Tools installer opened.');
        onOutput(
            '[+] Please complete the installation dialog, then check again.');
        return 0;
      } catch (e) {
        onOutput('[ERROR] $e');
        return -1;
      }
    }

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      String lastLine = '';
      final stdoutDone = process.stdout.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) {
            continue;
          }
          lastLine = cleaned;
          onOutput(cleaned);
        }
      }).asFuture();

      final stderrDone = process.stderr.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) {
            continue;
          }
          lastLine = cleaned;
          onOutput('[WARN] $cleaned');
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onOutput('');
        onOutput('[+] Git installed successfully!');
        if (PlatformService.isWindows) {
          onOutput('[+] Please restart the app for Git to be detected.');
        }
      } else {
        onOutput('');
        onOutput('[ERROR] Installation failed with exit code $exitCode');
      }
      return exitCode;
    } catch (e) {
      onOutput('[ERROR] $e');
      return -1;
    }
  }
}
