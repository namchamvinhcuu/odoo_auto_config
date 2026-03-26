import 'dart:io';
import '../models/command_result.dart';

class CommandRunner {
  static Future<CommandResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    bool runInShell = true,
  }) async {
    try {
      final result = await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
      );
      return CommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
    } catch (e) {
      return CommandResult(
        exitCode: -1,
        stdout: '',
        stderr: e.toString(),
      );
    }
  }
}
