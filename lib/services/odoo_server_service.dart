import 'dart:io';

/// Spawns and terminates an Odoo server process (`python odoo-bin ...`).
///
/// Pure IO helper — process lifecycle/state is owned by the Riverpod notifier.
/// The process is started in *normal* mode (NOT detached) so stdout/stderr can
/// be streamed to the in-app log and the process can be killed.
class OdooServerService {
  /// Start `python odoo-bin <args>` in [workingDirectory].
  ///
  /// [python] and [odooBin] are absolute paths (resolved from launch.json /
  /// venv), so `runInShell` is `false` on every OS — no shell word-splitting
  /// on paths that may contain spaces, and the exact interpreter is used.
  static Future<Process> start({
    required String python,
    required String odooBin,
    required List<String> args,
    required String workingDirectory,
  }) {
    return Process.start(
      python,
      [odooBin, ...args],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
  }

  /// Terminate the server and any workers it spawned (Odoo prefork).
  ///
  /// `process.kill()` alone only signals the parent, leaving prefork workers
  /// orphaned. Windows uses `taskkill /T` (tree); Unix kills direct children
  /// via `pkill -P` then SIGTERM→SIGKILL the parent with a short grace period.
  static Future<void> killTree(Process process) async {
    final pid = process.pid;
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/PID', '$pid', '/T', '/F'],
            runInShell: true);
      } catch (_) {}
      return;
    }

    // Unix: children first, then the parent.
    try {
      await Process.run('pkill', ['-TERM', '-P', '$pid']);
    } catch (_) {}
    process.kill(ProcessSignal.sigterm);

    // Grace period, then force-kill anything still alive.
    await Future.delayed(const Duration(milliseconds: 800));
    try {
      await Process.run('pkill', ['-KILL', '-P', '$pid']);
    } catch (_) {}
    process.kill(ProcessSignal.sigkill);
  }
}
