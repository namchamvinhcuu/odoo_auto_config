// Unit test cho OdooLaunchConfigService.resolve(projectPath).
//
// Feature: "chạy Odoo server làm background process". resolve() là single
// source of truth dựng lệnh `python odoo-bin -c odoo.conf --dev xml` từ
// .vscode/launch.json (khớp VscodeConfigService.generate), có fallback khi
// launch.json thiếu/hỏng.
//
// Test dùng temp dir thật (Directory.systemTemp.createTemp) — chạm File I/O
// thật, cleanup trong tearDown. Không mock filesystem vì resolve() dựa trực
// tiếp vào File.exists().

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/odoo_launch_config_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('odoo_launch_cfg_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Ghi 1 file (tạo parent dir nếu cần) bên trong [tempDir].
  Future<File> writeFile(String relative, String content) async {
    final f = File(p.join(tempDir.path, relative));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
    return f;
  }

  group('OdooLaunchConfigService.resolve — launch.json hợp lệ', () {
    test('resolve python + odooBin + args + confPath từ launch.json, isRunnable true',
        () async {
      // Arrange: launch.json giống VscodeConfigService.generate.
      const launchJson = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Odoo",
      "type": "python",
      "request": "launch",
      "python": "/opt/venv/bin/python",
      "program": "\${workspaceFolder}/odoo/odoo-bin",
      "args": ["-c", "\${workspaceFolder}/odoo.conf", "--dev", "xml"]
    }
  ]
}
''';
      await writeFile('.vscode/launch.json', launchJson);

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert
      expect(config.python, '/opt/venv/bin/python');
      expect(config.odooBin, p.join(tempDir.path, 'odoo', 'odoo-bin'));
      expect(config.args,
          ['-c', p.join(tempDir.path, 'odoo.conf'), '--dev', 'xml']);
      expect(config.confPath, p.join(tempDir.path, 'odoo.conf'));
      expect(config.workingDirectory, tempDir.path);
      expect(config.isRunnable, isTrue);
    });
  });

  group('OdooLaunchConfigService.resolve — fallback không có launch.json', () {
    test('synthesize command từ odoo/odoo-bin + venv/bin/python + odoo.conf',
        () async {
      // Arrange: không có launch.json, chỉ có file thật cho fallback.
      // Trên Linux venvPython('venv') = 'venv/bin/python'.
      await writeFile('odoo/odoo-bin', '#!/usr/bin/env python\n');
      await writeFile('venv/bin/python', '');
      await writeFile('odoo.conf', '[options]\n');

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert: path fallback đúng.
      expect(config.odooBin, p.join(tempDir.path, 'odoo', 'odoo-bin'));
      expect(config.python, p.join(tempDir.path, 'venv', 'bin', 'python'));
      expect(config.confPath, p.join(tempDir.path, 'odoo.conf'));
      // Args được synthesize khi launch.json không cấp.
      expect(config.args,
          ['-c', p.join(tempDir.path, 'odoo.conf'), '--dev', 'xml']);
      expect(config.isRunnable, isTrue);
    });
  });

  group('OdooLaunchConfigService.resolve — launch.json malformed', () {
    test('JSON hỏng không throw, rơi về fallback', () async {
      // Arrange: launch.json cú pháp hỏng + có file fallback thật.
      await writeFile('.vscode/launch.json', '{ this is : not valid json ]');
      await writeFile('odoo/odoo-bin', '#!/usr/bin/env python\n');
      await writeFile('venv/bin/python', '');
      await writeFile('odoo.conf', '[options]\n');

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert: không throw, dùng fallback.
      expect(config.python, p.join(tempDir.path, 'venv', 'bin', 'python'));
      expect(config.odooBin, p.join(tempDir.path, 'odoo', 'odoo-bin'));
      expect(config.confPath, p.join(tempDir.path, 'odoo.conf'));
      expect(config.args,
          ['-c', p.join(tempDir.path, 'odoo.conf'), '--dev', 'xml']);
      expect(config.isRunnable, isTrue);
    });
  });

  group('OdooLaunchConfigService.resolve — không đủ điều kiện chạy', () {
    test('thiếu cả python lẫn odoo-bin → isRunnable false', () async {
      // Arrange: temp dir rỗng (không launch.json, không odoo-bin, không venv).

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert
      expect(config.python, isNull);
      expect(config.odooBin, isNull);
      expect(config.isRunnable, isFalse);
      expect(config.workingDirectory, tempDir.path);
    });
  });

  group('OdooLaunchConfigService.resolve — httpPort detection', () {
    // Feature: detect server-ready qua port thay vì log line (fix bug
    // log_level=error làm mất dòng "HTTP running"). Arg --http-port thắng conf.

    test('đọc http_port từ odoo.conf khi args không có --http-port', () async {
      // Arrange: launch.json trỏ -c ${workspaceFolder}/odoo.conf, conf có port.
      const launchJson = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Odoo",
      "type": "python",
      "python": "/opt/venv/bin/python",
      "program": "\${workspaceFolder}/odoo/odoo-bin",
      "args": ["-c", "\${workspaceFolder}/odoo.conf", "--dev", "xml"]
    }
  ]
}
''';
      await writeFile('.vscode/launch.json', launchJson);
      await writeFile('odoo.conf', '[options]\nhttp_port = 8093\n');

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert
      expect(config.httpPort, 8093);
    });

    test('lấy http_port từ arg --http-port trong launch.json', () async {
      // Arrange: args có --http-port nhưng KHÔNG có -c → không đọc conf.
      const launchJson = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Odoo",
      "type": "python",
      "python": "/opt/venv/bin/python",
      "program": "\${workspaceFolder}/odoo/odoo-bin",
      "args": ["--http-port", "8099", "--dev", "xml"]
    }
  ]
}
''';
      await writeFile('.vscode/launch.json', launchJson);

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert
      expect(config.httpPort, 8099);
    });

    test('httpPort null khi không có ở conf lẫn args', () async {
      // Arrange: launch.json trỏ conf nhưng conf KHÔNG có dòng http_port.
      const launchJson = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Odoo",
      "type": "python",
      "python": "/opt/venv/bin/python",
      "program": "\${workspaceFolder}/odoo/odoo-bin",
      "args": ["-c", "\${workspaceFolder}/odoo.conf", "--dev", "xml"]
    }
  ]
}
''';
      await writeFile('.vscode/launch.json', launchJson);
      await writeFile('odoo.conf', '[options]\ndb_host = localhost\n');

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert
      expect(config.httpPort, isNull);
    });

    test('arg --http-port thắng http_port trong conf', () async {
      // Arrange: cả -c (conf có 8093) lẫn --http-port (8099) trong args.
      const launchJson = '''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Odoo",
      "type": "python",
      "python": "/opt/venv/bin/python",
      "program": "\${workspaceFolder}/odoo/odoo-bin",
      "args": ["-c", "\${workspaceFolder}/odoo.conf", "--http-port", "8099"]
    }
  ]
}
''';
      await writeFile('.vscode/launch.json', launchJson);
      await writeFile('odoo.conf', '[options]\nhttp_port = 8093\n');

      // Act
      final config = await OdooLaunchConfigService.resolve(tempDir.path);

      // Assert: arg override conf.
      expect(config.httpPort, 8099);
    });
  });
}
