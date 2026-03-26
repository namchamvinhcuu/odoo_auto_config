import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/folder_structure_config.dart';

class FolderStructureService {
  Future<List<String>> generate(FolderStructureConfig config) async {
    final logs = <String>[];
    final basePath = config.projectPath;

    // Create base directory
    await _createDir(basePath, logs);

    // Create odoo symlink to source code
    if (config.odooSourcePath.isNotEmpty) {
      await _createSymlink(
          config.odooSourcePath, p.join(basePath, 'odoo'), logs);
    }

    if (config.createAddons) {
      await _createDir(p.join(basePath, 'addons'), logs);
    }

    if (config.createThirdPartyAddons) {
      await _createDir(p.join(basePath, 'third_party_addons'), logs);
    }

    // Create filestore directory
    await _createDir(p.join(basePath, 'filestore'), logs);

    return logs;
  }

  Future<void> _createSymlink(
    String target,
    String linkPath,
    List<String> logs,
  ) async {
    final link = Link(linkPath);
    if (await link.exists()) {
      logs.add('[=] Symlink exists: $linkPath -> ${await link.target()}');
      return;
    }
    if (await Directory(linkPath).exists()) {
      logs.add('[WARN] Directory already exists at $linkPath, skipping symlink');
      return;
    }
    await link.create(target);
    logs.add('[+] Symlink: $linkPath -> $target');
  }

  Future<void> _createDir(String path, List<String> logs) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      logs.add('[+] Created: $path');
    } else {
      logs.add('[=] Exists: $path');
    }
  }
}
