import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'command_runner.dart';
import 'platform_service.dart';

class PythonVersion {
  final String version;
  final String label;

  const PythonVersion(this.version, this.label);
}

class PythonInstallService {
  static const availableVersions = [
    PythonVersion('3.13', 'Python 3.13'),
    PythonVersion('3.12', 'Python 3.12'),
    PythonVersion('3.11', 'Python 3.11'),
    PythonVersion('3.10', 'Python 3.10'),
  ];

  /// Returns the install command and args for the current platform.
  static ({String executable, List<String> args, String description})
      installCommand(String version) {
    if (PlatformService.isWindows) {
      return (
        executable: 'winget',
        args: [
          'install',
          'Python.Python.$version',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install Python.Python.$version',
      );
    } else if (PlatformService.isMacOS) {
      return (
        executable: 'brew',
        args: ['install', 'python@$version'],
        description: 'brew install python@$version',
      );
    } else if (PlatformService.isDnf) {
      return (
        executable: 'pkexec',
        args: ['dnf', 'install', '-y', 'python$version'],
        description: 'pkexec dnf install -y python$version',
      );
    } else {
      return (
        executable: 'pkexec',
        args: ['apt', 'install', '-y', 'python$version', 'python$version-venv'],
        description: 'pkexec apt install -y python$version python$version-venv',
      );
    }
  }

  /// Check if winget/brew/pkexec+apt/dnf is available.
  static Future<bool> isPackageManagerAvailable() async {
    try {
      if (PlatformService.isWindows) {
        final result =
            await Process.run('winget', ['--version'], runInShell: true);
        return result.exitCode == 0;
      } else if (PlatformService.isMacOS) {
        final result =
            await Process.run('brew', ['--version'], runInShell: true);
        return result.exitCode == 0;
      } else {
        // Linux: need pkexec + (apt or dnf)
        final pkexecResult =
            await Process.run('which', ['pkexec'], runInShell: true);
        return pkexecResult.exitCode == 0 &&
            PlatformService.linuxPackageManager != null;
      }
    } catch (_) {
      return false;
    }
  }

  /// Install Python with real-time output via callback.
  static Future<int> install(
    String version,
    void Function(String line) onOutput,
  ) async {
    final cmd = installCommand(version);
    onOutput('[+] Running: ${cmd.description}');
    onOutput('');

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      String lastLine = '';
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder && lastLine == cleaned) continue;
          lastLine = cleaned;
          onOutput(cleaned);
        }
      }).asFuture();

      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder && lastLine == cleaned) continue;
          lastLine = cleaned;
          onOutput('[WARN] $cleaned');
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onOutput('');
        onOutput('[+] Python $version installed successfully!');
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

  /// Returns the uninstall command for the current platform.
  /// [version] should be major.minor (e.g. "3.11").
  static ({String executable, List<String> args, String description})?
      uninstallCommand(String version) {
    if (PlatformService.isWindows) {
      return (
        executable: 'winget',
        args: [
          'uninstall',
          'Python.Python.$version',
          '--accept-source-agreements',
        ],
        description: 'winget uninstall Python.Python.$version',
      );
    } else if (PlatformService.isMacOS) {
      return (
        executable: 'brew',
        args: ['uninstall', 'python@$version'],
        description: 'brew uninstall python@$version',
      );
    } else if (PlatformService.isDnf) {
      return (
        executable: 'pkexec',
        args: ['dnf', 'remove', '-y', 'python$version'],
        description: 'pkexec dnf remove -y python$version',
      );
    } else {
      return (
        executable: 'pkexec',
        args: ['apt', 'remove', '-y', 'python$version'],
        description: 'pkexec apt remove -y python$version',
      );
    }
  }

  /// Uninstall Python with real-time output via callback.
  static Future<int> uninstall(
    String version,
    void Function(String line) onOutput,
  ) async {
    final cmd = uninstallCommand(version);
    if (cmd == null) {
      onOutput('[ERROR] Uninstall not supported on this platform');
      return -1;
    }
    onOutput('[+] Running: ${cmd.description}');
    onOutput('');

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      String lastLine = '';
      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) { continue; }
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) { continue; }
          lastLine = cleaned;
          onOutput(cleaned);
        }
      }).asFuture();

      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) { continue; }
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) { continue; }
          lastLine = cleaned;
          onOutput('[WARN] $cleaned');
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onOutput('');
        onOutput('[+] Python $version uninstalled successfully!');
      } else {
        onOutput('');
        onOutput('[ERROR] Uninstall failed with exit code $exitCode');
      }

      return exitCode;
    } catch (e) {
      onOutput('[ERROR] $e');
      return -1;
    }
  }
}
