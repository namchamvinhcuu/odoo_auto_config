import 'dart:io';
import '../models/command_result.dart';

class CommandRunner {
  static Future<CommandResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    try {
      final result = await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory,
        runInShell: runInShell,
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
