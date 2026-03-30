import 'dart:convert';
import 'dart:io';
import 'command_runner.dart';
import 'platform_service.dart';

class DockerInstallService {
  /// Check if Docker is installed
  static Future<bool> isInstalled() async {
    try {
      final docker = await PlatformService.dockerPath;
      final result =
          await Process.run(docker, ['--version'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Check if Docker daemon is running
  static Future<bool> isRunning() async {
    try {
      final docker = await PlatformService.dockerPath;
      final result =
          await Process.run(docker, ['info'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get Docker version string
  static Future<String?> getVersion() async {
    try {
      final docker = await PlatformService.dockerPath;
      final result =
          await Process.run(docker, ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  /// Get Docker Compose version string
  static Future<String?> getComposeVersion() async {
    try {
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
          docker, ['compose', 'version'], runInShell: true);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  /// Install command for current platform
  static ({String executable, List<String> args, String description})
      installCommand() {
    if (PlatformService.isWindows) {
      return (
        executable: 'winget',
        args: [
          'install',
          'Docker.DockerDesktop',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install Docker.DockerDesktop',
      );
    } else if (PlatformService.isMacOS) {
      return (
        executable: 'brew',
        args: ['install', '--cask', 'docker'],
        description: 'brew install --cask docker',
      );
    } else {
      return (
        executable: 'pkexec',
        args: [
          'bash',
          '-c',
          'apt update && apt install -y docker.io docker-compose-v2 && systemctl enable --now docker',
        ],
        description:
            'apt install docker.io docker-compose-v2 && systemctl enable docker',
      );
    }
  }

  /// Check if WSL is installed (Windows only)
  static Future<bool> isWslInstalled() async {
    if (!PlatformService.isWindows) return true;
    try {
      final result =
          await Process.run('wsl', ['--status'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Install WSL on Windows (requires elevation via UAC)
  static Future<int> _installWsl(void Function(String line) onOutput) async {
    onOutput('[+] WSL not found. Installing WSL...');
    onOutput('[+] Running: wsl --install --no-distribution (Administrator)');
    onOutput('');

    try {
      // Use PowerShell Start-Process -Verb RunAs to elevate
      final process = await Process.start(
        'powershell',
        [
          '-Command',
          'Start-Process wsl -ArgumentList "--install","--no-distribution" -Verb RunAs -Wait',
        ],
        runInShell: true,
      );

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          onOutput(cleaned);
        }
      }).asFuture();

      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          onOutput('[WARN] $cleaned');
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onOutput('');
        onOutput('[+] WSL installed successfully!');
        onOutput('');
        onOutput('[WARN] Please RESTART your computer, then come back to install Docker.');
      } else {
        onOutput('');
        onOutput('[ERROR] WSL installation failed with exit code $exitCode');
      }
      return exitCode;
    } catch (e) {
      onOutput('[ERROR] $e');
      return -1;
    }
  }

  /// Install Docker with real-time output
  static Future<int> install(void Function(String line) onOutput) async {
    // Windows: install WSL first if needed
    if (PlatformService.isWindows) {
      final wslOk = await isWslInstalled();
      if (!wslOk) {
        final wslExit = await _installWsl(onOutput);
        // WSL needs restart before Docker can be installed
        return wslExit;
      }
    }

    final cmd = installCommand();
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
        onOutput('[+] Docker installed successfully!');
        if (PlatformService.isMacOS || PlatformService.isWindows) {
          onOutput('[+] Please open Docker Desktop to start the daemon.');
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
