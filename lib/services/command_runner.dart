import 'dart:io';
import '../models/command_result.dart';

class CommandRunner {
  static Map<String, String>? _shellEnv;

  /// Loads the full environment from the user's login shell once.
  /// On macOS, GUI apps don't source ~/.zshrc so PATH is minimal.
  /// This runs `zsh -lc env` to get the real environment.
  static Future<Map<String, String>> _getShellEnv() async {
    if (_shellEnv != null) return _shellEnv!;

    if (!Platform.isMacOS) {
      _shellEnv = {};
      return _shellEnv!;
    }

    try {
      final result = await Process.run(
        '/bin/zsh',
        ['-lc', 'env'],
      );
      if (result.exitCode == 0) {
        final env = <String, String>{};
        for (final line in (result.stdout as String).split('\n')) {
          final idx = line.indexOf('=');
          if (idx > 0) {
            env[line.substring(0, idx)] = line.substring(idx + 1);
          }
        }
        _shellEnv = env;
        return _shellEnv!;
      }
    } catch (_) {}

    _shellEnv = {};
    return _shellEnv!;
  }

  static Future<CommandResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    try {
      final env = await _getShellEnv();
      final result = await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory,
        runInShell: runInShell,
        environment: env.isNotEmpty ? env : null,
      );
      return CommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
    } on ProcessException catch (e) {
      return CommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.message,
      );
    }
  }
}
