import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'platform_service.dart';

class VscodeConfigService {
  Future<List<String>> generate({
    required String projectPath,
    required String configName,
    required String venvPath,
    required String odooBinPath,
  }) async {
    final logs = <String>[];
    final vscodePath = p.join(projectPath, '.vscode');

    final dir = Directory(vscodePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      logs.add('[+] Created: $vscodePath');
    } else {
      logs.add('[=] Exists: $vscodePath');
    }

    final config = {
      'name': configName,
      'type': 'debugpy',
      'request': 'launch',
      'python': PlatformService.venvPython(venvPath),
      'program': odooBinPath,
      'args': ['-c', '\${workspaceFolder}/odoo.conf', '--dev', 'xml'],
      'env': <String, dynamic>{},
      'console': 'integratedTerminal',
      'justMyCode': false,
    };

    final launch = {
      'version': '0.2.0',
      'configurations': [config],
    };

    final launchPath = p.join(vscodePath, 'launch.json');
    final launchFile = File(launchPath);

    // Merge if exists
    if (await launchFile.exists()) {
      try {
        final existing =
            jsonDecode(await launchFile.readAsString()) as Map<String, dynamic>;
        final existingConfigs =
            (existing['configurations'] as List<dynamic>?) ?? [];
        existingConfigs.removeWhere((c) => c['name'] == configName);
        existingConfigs.add(config);
        launch['configurations'] = existingConfigs;
        logs.add('[+] Merged into existing launch.json');
      } catch (_) {
        logs.add('[WARN] Existing launch.json invalid, overwriting');
      }
    }

    await launchFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(launch),
    );
    logs.add('[+] Written: $launchPath');

    return logs;
  }
}
