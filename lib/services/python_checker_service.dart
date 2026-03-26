import '../models/python_info.dart';
import 'command_runner.dart';
import 'platform_service.dart';

class PythonCheckerService {
  Future<List<PythonInfo>> detectAll() async {
    final List<PythonInfo> results = [];
    final seen = <String>{};

    for (final candidate in PlatformService.pythonCandidates) {
      final info = await _checkPython(candidate);
      if (info != null && !seen.contains(info.executablePath)) {
        seen.add(info.executablePath);
        results.add(info);
      }
    }

    if (PlatformService.isWindows) {
      final pyLauncherResults = await _checkPyLauncher();
      for (final info in pyLauncherResults) {
        if (!seen.contains(info.executablePath)) {
          seen.add(info.executablePath);
          results.add(info);
        }
      }
    }

    // Remove shim entries that resolve to the same version as a real binary.
    // e.g. pyenv shim reporting 3.9.6 is redundant when /usr/bin/python3 3.9.6 exists.
    if (PlatformService.isMacOS) {
      final realEntries = results
          .where((r) => !r.executablePath.contains('/shims/'))
          .map((r) => r.version)
          .toSet();
      results.removeWhere(
          (r) => r.executablePath.contains('/shims/') && realEntries.contains(r.version));
    }

    return results;
  }

  Future<PythonInfo?> _checkPython(String executable) async {
    final versionResult = await CommandRunner.run(executable, ['--version']);
    if (!versionResult.isSuccess) return null;

    final versionStr = versionResult.stdout.isNotEmpty
        ? versionResult.stdout
        : versionResult.stderr;
    final version = _parseVersion(versionStr);
    if (version.isEmpty) return null;

    // Get the real path
    String realPath = executable;
    if (PlatformService.isLinux || PlatformService.isMacOS) {
      final whichResult = await CommandRunner.run('which', [executable]);
      if (whichResult.isSuccess) {
        realPath = whichResult.stdout;
      }
    } else if (PlatformService.isWindows) {
      final whereResult =
          await CommandRunner.run('where', [executable], runInShell: true);
      if (whereResult.isSuccess) {
        realPath = whereResult.stdout.split('\n').first.trim();
      }
    }

    // Check pip
    final pipResult =
        await CommandRunner.run(executable, ['-m', 'pip', '--version']);
    final hasPip = pipResult.isSuccess;
    String pipVersion = '';
    if (hasPip) {
      pipVersion = _parsePipVersion(pipResult.stdout);
    }

    // Check venv module
    final venvResult =
        await CommandRunner.run(executable, ['-c', 'import venv']);
    final hasVenv = venvResult.isSuccess;

    return PythonInfo(
      executablePath: realPath,
      version: version,
      hasPip: hasPip,
      pipVersion: pipVersion,
      hasVenv: hasVenv,
    );
  }

  Future<List<PythonInfo>> _checkPyLauncher() async {
    final result = await CommandRunner.run('py', ['--list'], runInShell: true);
    if (!result.isSuccess) return [];

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
