import 'dart:io';
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

  /// Install Docker with real-time output
  static Future<int> install(void Function(String line) onOutput) async {
    final cmd = installCommand();
    onOutput('[+] Running: ${cmd.description}');
    onOutput('');

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      final stdoutDone = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) onOutput(line);
        }
      }).asFuture();

      final stderrDone = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) onOutput('[WARN] $line');
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
