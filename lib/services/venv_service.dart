import 'dart:io';
import '../models/command_result.dart';
import '../models/venv_config.dart';
import '../models/venv_info.dart';
import 'command_runner.dart';
import 'platform_service.dart';

class VenvService {
  /// Scan a directory for existing venvs (looks for pyvenv.cfg marker file)
  Future<List<VenvInfo>> scanForVenvs(String directory, {int maxDepth = 2}) async {
    final results = <VenvInfo>[];
    final dir = Directory(directory);
    if (!await dir.exists()) return results;

    await _scanDir(dir, results, 0, maxDepth);
    return results;
  }

  Future<void> _scanDir(
    Directory dir,
    List<VenvInfo> results,
    int currentDepth,
    int maxDepth,
  ) async {
    if (currentDepth > maxDepth) return;

    try {
      final cfgFile = File('${dir.path}/pyvenv.cfg');
      if (await cfgFile.exists()) {
        final info = await inspectVenv(dir.path);
        if (info != null) results.add(info);
        return; // Don't scan inside a venv
      }

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.path.split('/').last.split('\\').last;
          if (name.startsWith('.')) continue; // Skip hidden dirs
          await _scanDir(entity, results, currentDepth + 1, maxDepth);
        }
      }
    } on FileSystemException {
      // Permission denied, skip
    }
  }

  Future<VenvInfo?> inspectVenv(String venvPath) async {
    final pythonExe = PlatformService.venvPython(venvPath);
    final isValid = await File(pythonExe).exists();

    String pythonVersion = '';
    String pipVersion = '';

    if (isValid) {
      final versionResult = await CommandRunner.run(pythonExe, ['--version']);
      if (versionResult.isSuccess) {
        final match = RegExp(r'Python (\S+)').firstMatch(versionResult.stdout);
        pythonVersion = match?.group(1) ?? '';
      }

      final pipExe = PlatformService.venvPip(venvPath);
      final pipResult = await CommandRunner.run(pipExe, ['--version']);
      if (pipResult.isSuccess) {
        final match = RegExp(r'pip (\S+)').firstMatch(pipResult.stdout);
        pipVersion = match?.group(1) ?? '';
      }
    }

    return VenvInfo(
      path: venvPath,
      pythonVersion: pythonVersion,
      pipVersion: pipVersion,
      isValid: isValid,
    );
  }

  Future<CommandResult> createVenv(VenvConfig config) async {
    final targetDir = Directory(config.targetDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    return CommandRunner.run(
      config.pythonPath,
      ['-m', 'venv', config.fullPath],
    );
  }

  Future<bool> validateVenv(String venvPath) async {
    final pythonPath = PlatformService.venvPython(venvPath);
    return File(pythonPath).exists();
  }

  Future<CommandResult> installRequirements(
    String venvPath,
    String requirementsFile,
  ) async {
    final pip = PlatformService.venvPip(venvPath);
    return CommandRunner.run(pip, ['install', '-r', requirementsFile]);
  }

  Future<CommandResult> installPackage(
    String venvPath,
    String packageName,
  ) async {
    final pip = PlatformService.venvPip(venvPath);
    return CommandRunner.run(pip, ['install', packageName]);
  }
}
