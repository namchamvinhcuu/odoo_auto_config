import 'dart:io';
import '../models/python_info.dart';
import 'platform_service.dart';

class PythonCheckerService {
  Future<List<PythonInfo>> detectAll() async {
    final List<PythonInfo> results = [];
    final seen = <String>{};

    for (final candidate in PlatformService.pythonCandidates) {
      try {
        final info = await _checkPython(candidate);
        if (info != null && !seen.contains(info.executablePath)) {
          seen.add(info.executablePath);
          results.add(info);
        }
      } catch (_) {
        // Skip candidates that cause errors
      }
    }

    if (PlatformService.isWindows) {
      try {
        final pyLauncherResults = await _checkPyLauncher();
        for (final info in pyLauncherResults) {
          if (!seen.contains(info.executablePath)) {
            seen.add(info.executablePath);
            results.add(info);
          }
        }
      } catch (_) {}
    }

    // Remove shim entries that resolve to the same version as a real binary.
    if (PlatformService.isMacOS || PlatformService.isLinux) {
      final realEntries = results
          .where((r) => !r.executablePath.contains('/shims/'))
          .map((r) => r.version)
          .toSet();
      results.removeWhere((r) =>
          r.executablePath.contains('/shims/') &&
          realEntries.contains(r.version));
    }

    return results;
  }

  Future<PythonInfo?> _checkPython(String executable) async {
    // Check if absolute path exists before trying to run it
    if (executable.startsWith('/')) {
      if (!File(executable).existsSync()) return null;
    }

    final versionResult = await _run(executable, ['--version']);
    if (versionResult == null || versionResult.exitCode != 0) return null;

    final versionStr = versionResult.stdout.isNotEmpty
        ? versionResult.stdout
        : versionResult.stderr;
    final version = _parseVersion(versionStr);
    if (version.isEmpty) return null;

    // Get the real path
    String realPath = executable;
    if (PlatformService.isLinux || PlatformService.isMacOS) {
      final whichResult = await _run('which', [executable]);
      if (whichResult != null && whichResult.exitCode == 0) {
        realPath = whichResult.stdout;
      }
    } else if (PlatformService.isWindows) {
      final whereResult = await _run('where', [executable], runInShell: true);
      if (whereResult != null && whereResult.exitCode == 0) {
        realPath = whereResult.stdout.split('\n').first.trim();
      }
    }

    // Check pip
    final pipResult = await _run(executable, ['-m', 'pip', '--version']);
    final hasPip = pipResult != null && pipResult.exitCode == 0;
    String pipVersion = '';
    if (hasPip) {
      pipVersion = _parsePipVersion(pipResult.stdout);
    }

    // Check venv module
    final venvResult = await _run(executable, ['-c', 'import venv']);
    final hasVenv = venvResult != null && venvResult.exitCode == 0;

    return PythonInfo(
      executablePath: realPath,
      version: version,
      hasPip: hasPip,
      pipVersion: pipVersion,
      hasVenv: hasVenv,
    );
  }

  /// Runs a process via shell to avoid native crashes in release mode.
  Future<_SimpleResult?> _run(
    String executable,
    List<String> args, {
    bool runInShell = true,
  }) async {
    try {
      final result = await Process.run(
        executable,
        args,
        runInShell: true,
      );
      return _SimpleResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString().trim(),
        stderr: result.stderr.toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<PythonInfo>> _checkPyLauncher() async {
    final result = await _run('py', ['--list'], runInShell: true);
    if (result == null || result.exitCode != 0) return [];

    final List<PythonInfo> results = [];
    final lines = result.stdout.split('\n');
    for (final line in lines) {
      final match = RegExp(r'-V:(\d+\.\d+)').firstMatch(line);
      if (match != null) {
        final ver = match.group(1)!;
        final info = await _checkPython('py -$ver');
        if (info != null) results.add(info);
      }
    }
    return results;
  }

  String _parseVersion(String output) {
    final match = RegExp(r'Python (\d+\.\d+\.\d+)').firstMatch(output);
    return match?.group(1) ?? '';
  }

  String _parsePipVersion(String output) {
    final match = RegExp(r'pip (\S+)').firstMatch(output);
    return match?.group(1) ?? '';
  }
}

class _SimpleResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  _SimpleResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}
