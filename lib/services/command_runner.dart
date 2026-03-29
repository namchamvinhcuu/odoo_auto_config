import 'dart:io';
import '../models/command_result.dart';

class CommandRunner {
  /// Regex to strip ANSI/VT100 escape sequences from terminal output
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]|\x1B\].*?\x07');

  /// Placeholder returned for spinner/progress lines
  static const spinnerPlaceholder = '...';

  /// Spinner characters used by winget/brew for terminal animation
  static final _spinnerRegex = RegExp(r'^[\s\\|/\-]+$');

  /// Clean a line of process output: strip ANSI codes, handle \r
  /// Returns null if the line should be filtered out (e.g. progress bars, spinners)
  static String? cleanLine(String line) {
    // Handle carriage return: take last segment (progress bar overwrites)
    if (line.contains('\r')) {
      line = line.split('\r').last;
    }
    // Strip ANSI escape sequences
    line = line.replaceAll(_ansiRegex, '').trim();
    if (line.isEmpty) return null;
    // Replace spinner lines (\ | / -) with a placeholder
    if (_spinnerRegex.hasMatch(line)) return spinnerPlaceholder;
    // Filter out lines that are mostly Unicode block characters (progress bars)
    final blockChars = RegExp(r'[░▏▎▍▌▋▊▉█▓▒─━]');
    final cleaned = line.replaceAll(blockChars, '').trim();
    if (cleaned.isEmpty) return null;
    return line;
  }
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
