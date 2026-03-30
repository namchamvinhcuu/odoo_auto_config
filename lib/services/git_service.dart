import 'dart:convert';
import 'dart:io';
import 'command_runner.dart';
import 'platform_service.dart';

class GitService {
  static Future<String> get gitPath async {
    if (PlatformService.isMacOS) {
      for (final path in [
        '/usr/bin/git',
        '/usr/local/bin/git',
        '/opt/homebrew/bin/git',
      ]) {
        if (await File(path).exists()) return path;
      }
    }
    return 'git';
  }

  static Future<bool> isInstalled() async {
    try {
      final git = await gitPath;
      final result = await Process.run(git, ['--version'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getVersion() async {
    try {
      final git = await gitPath;
      final result = await Process.run(git, ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final match =
            RegExp(r'git version (\S+)').firstMatch(result.stdout.toString());
        return match?.group(1);
      }
    } catch (_) {}
    return null;
  }

  static ({String executable, List<String> args, String description})
      installCommand() {
    if (PlatformService.isWindows) {
      return (
        executable: 'winget',
        args: [
          'install',
          '--id',
          'Git.Git',
          '-e',
          '--source',
          'winget',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install --id Git.Git',
      );
    } else if (PlatformService.isMacOS) {
      return (
        executable: 'xcode-select',
        args: ['--install'],
        description: 'xcode-select --install',
      );
    } else {
      return (
        executable: 'pkexec',
        args: ['apt', 'install', '-y', 'git'],
        description: 'pkexec apt install -y git',
      );
    }
  }

  static Future<int> install(void Function(String line) onOutput) async {
    final cmd = installCommand();
    onOutput('[+] Running: ${cmd.description}');
    onOutput('');

    if (PlatformService.isMacOS) {
      // xcode-select --install opens a system dialog
      try {
        await Process.run(cmd.executable, cmd.args, runInShell: true);
        onOutput('[+] Xcode Command Line Tools installer opened.');
        onOutput(
            '[+] Please complete the installation dialog, then check again.');
        return 0;
      } catch (e) {
        onOutput('[ERROR] $e');
        return -1;
      }
    }

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      String lastLine = '';
      final stdoutDone = process.stdout.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) {
            continue;
          }
          lastLine = cleaned;
          onOutput(cleaned);
        }
      }).asFuture();

      final stderrDone = process.stderr.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) {
            continue;
          }
          lastLine = cleaned;
          onOutput('[WARN] $cleaned');
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        onOutput('');
        onOutput('[+] Git installed successfully!');
        if (PlatformService.isWindows) {
          onOutput('[+] Please restart the app for Git to be detected.');
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
