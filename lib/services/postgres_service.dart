import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'command_runner.dart';
import 'platform_service.dart';
import 'storage_service.dart';
import 'package:odoo_auto_config/templates/postgres_templates.dart';

/// Represents a detected PostgreSQL server instance
class PgServerInfo {
  final PgServerSource source;
  final int port;
  final bool isReady;

  /// Docker-specific fields
  final String? containerName;
  final String? imageName;
  final bool? containerRunning;

  /// Local-specific fields
  final String? serviceName;

  const PgServerInfo({
    required this.source,
    required this.port,
    required this.isReady,
    this.containerName,
    this.imageName,
    this.containerRunning,
    this.serviceName,
  });
}

enum PgServerSource { docker, local }

class PostgresService {
  // ── Binary Resolution ──

  static Future<List<String>> get _macBinDirs async {
    final home = Platform.environment['HOME'] ?? '';
    final dirs = <String>[
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/opt/homebrew/opt/libpq/bin',
      '/usr/local/opt/libpq/bin',
      '/opt/homebrew/opt/postgresql/bin',
      '/usr/local/opt/postgresql/bin',
      '$home/.asdf/shims',
    ];
    final pgAppDir =
        Directory('/Applications/Postgres.app/Contents/Versions');
    if (await pgAppDir.exists()) {
      try {
        final versions = pgAppDir.listSync().whereType<Directory>().toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final ver in versions) {
          dirs.add('${ver.path}/bin');
        }
      } catch (_) {}
    }
    return dirs;
  }

  static List<String> get _linuxBinDirs => const [
        '/usr/bin',
        '/usr/local/bin',
        '/usr/lib/postgresql/bin',
      ];

  static Future<List<String>> get _linuxBinDirsExpanded async {
    final dirs = List<String>.from(_linuxBinDirs);
    final pgLibDir = Directory('/usr/lib/postgresql');
    if (await pgLibDir.exists()) {
      try {
        final versions = pgLibDir.listSync().whereType<Directory>().toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final ver in versions) {
          dirs.add('${ver.path}/bin');
        }
      } catch (_) {}
    }
    return dirs;
  }

  static Future<List<String>> get _winBinDirs async {
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final dirs = <String>[];
    final pgDir = Directory('$programFiles\\PostgreSQL');
    if (await pgDir.exists()) {
      try {
        final versions = pgDir.listSync().whereType<Directory>().toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final ver in versions) {
          dirs.add('${ver.path}\\bin');
        }
      } catch (_) {}
    }
    if (localAppData.isNotEmpty) {
      dirs.add('$localAppData\\Microsoft\\WinGet\\Links');
    }
    dirs.add(r'C:\ProgramData\chocolatey\bin');
    final home = Platform.environment['USERPROFILE'] ?? '';
    if (home.isNotEmpty) {
      dirs.add('$home\\scoop\\shims');
    }
    return dirs;
  }

  static Future<String> _resolveBin(String name) async {
    if (PlatformService.isMacOS) {
      for (final dir in await _macBinDirs) {
        final path = '$dir/$name';
        if (await File(path).exists()) return path;
      }
    } else if (PlatformService.isWindows) {
      for (final dir in await _winBinDirs) {
        final path = '$dir\\$name.exe';
        if (await File(path).exists()) return path;
      }
    } else {
      for (final dir in await _linuxBinDirsExpanded) {
        final path = '$dir/$name';
        if (await File(path).exists()) return path;
      }
    }
    return name;
  }

  static Future<String> get psqlPath => _resolveBin('psql');
  static Future<String> get pgIsReadyPath => _resolveBin('pg_isready');

  // ── Client Tools ──

  static const clientTools = [
    ('psql', 'Interactive terminal'),
    ('pg_dump', 'Backup database'),
    ('pg_restore', 'Restore database'),
    ('createdb', 'Create database'),
    ('dropdb', 'Drop database'),
    ('pg_isready', 'Check server status'),
  ];

  static Future<Map<String, String?>> detectClientTools() async {
    final result = <String, String?>{};
    for (final (name, _) in clientTools) {
      try {
        final path = await _resolveBin(name);
        final check =
            await Process.run(path, ['--version'], runInShell: true);
        result[name] = check.exitCode == 0 ? path : null;
      } catch (_) {
        result[name] = null;
      }
    }
    return result;
  }

  static Future<bool> isInstalled() async {
    try {
      final psql = await psqlPath;
      final result =
          await Process.run(psql, ['--version'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getVersion() async {
    try {
      final psql = await psqlPath;
      final result =
          await Process.run(psql, ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (_) {}
    return null;
  }

  // ── Settings (persistent storage) ──

  static Future<Map<String, dynamic>> loadSettings() async {
    final settings = await StorageService.loadSettings();
    return (settings['postgres'] as Map<String, dynamic>?) ?? {};
  }

  static Future<void> saveSettings(Map<String, dynamic> pg) async {
    await StorageService.updateSettings((settings) {
      settings['postgres'] = pg;
    });
  }

  // ── Server Detection ──

  static const _detectTimeout = Duration(seconds: 5);

  static Future<List<PgServerInfo>> detectServers() async {
    final results = await Future.wait([
      _detectDockerServers().timeout(_detectTimeout, onTimeout: () => []),
      _detectLocalServer().timeout(_detectTimeout, onTimeout: () => []),
    ]);
    return [...results[0], ...results[1]];
  }

  static Future<ProcessResult?> _runWithTimeout(
      String exe, List<String> args) async {
    try {
      return await Process.run(exe, args, runInShell: true)
          .timeout(_detectTimeout);
    } catch (_) {
      return null;
    }
  }

  /// Detect Docker containers (running + stopped) that have internal port 5432
  static Future<List<PgServerInfo>> _detectDockerServers() async {
    try {
      final docker = await PlatformService.dockerPath;
      // Use -a to include stopped containers
      final result = await _runWithTimeout(
          docker, ['ps', '-a', '--format', '{{json .}}']);
      if (result == null || result.exitCode != 0) return [];

      final lines = result.stdout
          .toString()
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty);

      final servers = <PgServerInfo>[];

      for (final line in lines) {
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final ports = (json['Ports'] ?? '').toString();
          final status = (json['State'] ?? '').toString().toLowerCase();
          final isRunning = status == 'running';

          // For running containers: check port mapping
          // For stopped containers: check image name contains postgres
          int? hostPort = _extractHostPort(ports, 5432);
          final image = (json['Image'] ?? '').toString().toLowerCase();
          if (hostPort == null) {
            // No port mapping found: check if image is postgres
            if (!image.contains('postgres')) continue;
            // Try to get port from container inspect
            hostPort = await _getContainerPort(
                docker, (json['Names'] ?? '').toString());
            hostPort ??= 5432; // default
          }

          final containerName = (json['Names'] ?? '').toString();

          final isReady =
              isRunning ? await _checkPgReady(hostPort) : false;

          servers.add(PgServerInfo(
            source: PgServerSource.docker,
            port: hostPort,
            isReady: isReady,
            containerName: containerName,
            imageName: (json['Image'] ?? '').toString(),
            containerRunning: isRunning,
          ));
        } catch (_) {
          continue;
        }
      }
      return servers;
    } catch (_) {
      return [];
    }
  }

  /// Get host port from stopped container via docker inspect
  static Future<int?> _getContainerPort(
      String docker, String containerName) async {
    if (containerName.isEmpty) return null;
    try {
      final result = await _runWithTimeout(docker, [
        'inspect',
        '--format',
        '{{json .HostConfig.PortBindings}}',
        containerName,
      ]);
      if (result == null || result.exitCode != 0) return null;
      final output = result.stdout.toString().trim();
      if (output.isEmpty || output == 'null') return null;
      final bindings = jsonDecode(output) as Map<String, dynamic>;
      // Look for 5432/tcp binding
      final pgBindings = bindings['5432/tcp'];
      if (pgBindings is List && pgBindings.isNotEmpty) {
        final hostPort = pgBindings[0]['HostPort']?.toString();
        if (hostPort != null) return int.tryParse(hostPort);
      }
    } catch (_) {}
    return null;
  }

  static int? _extractHostPort(String portsStr, int internalPort) {
    final regex = RegExp(r'(\d+)->(\d+)/');
    for (final match in regex.allMatches(portsStr)) {
      final containerPort = int.tryParse(match.group(2) ?? '');
      if (containerPort == internalPort) {
        return int.tryParse(match.group(1) ?? '');
      }
    }
    return null;
  }

  static Future<List<PgServerInfo>> _detectLocalServer() async {
    try {
      if (PlatformService.isMacOS) {
        return _detectLocalMacOS();
      } else if (PlatformService.isLinux) {
        return _detectLocalLinux();
      } else {
        return _detectLocalWindows();
      }
    } catch (_) {
      return [];
    }
  }

  static Future<List<PgServerInfo>> _detectLocalMacOS() async {
    final brew = await PlatformService.brewPath;
    final result = await _runWithTimeout(brew, ['services', 'list']);
    if (result == null || result.exitCode != 0) return [];

    final output = result.stdout.toString();
    final pgRegex = RegExp(r'(postgresql\S*)\s+started', caseSensitive: false);
    final match = pgRegex.firstMatch(output);
    if (match == null) return _detectPostgresApp();

    final serviceName = match.group(1) ?? 'postgresql';
    const port = 5432;
    final isReady = await _checkPgReady(port);

    return [
      PgServerInfo(
        source: PgServerSource.local,
        port: port,
        isReady: isReady,
        serviceName: serviceName,
      ),
    ];
  }

  static Future<List<PgServerInfo>> _detectPostgresApp() async {
    const port = 5432;
    final isReady = await _checkPgReady(port);
    if (!isReady) return [];

    try {
      final result = await _runWithTimeout('pgrep', ['-fl', 'Postgres.app']);
      if (result != null &&
          result.exitCode == 0 &&
          result.stdout.toString().contains('Postgres.app')) {
        return [
          PgServerInfo(
            source: PgServerSource.local,
            port: port,
            isReady: true,
            serviceName: 'Postgres.app',
          ),
        ];
      }
    } catch (_) {}
    return [];
  }

  static Future<List<PgServerInfo>> _detectLocalLinux() async {
    final result =
        await _runWithTimeout('systemctl', ['is-active', 'postgresql']);
    if (result == null || result.exitCode != 0) return [];

    final status = result.stdout.toString().trim();
    if (status != 'active') return [];

    const port = 5432;
    final isReady = await _checkPgReady(port);

    return [
      PgServerInfo(
        source: PgServerSource.local,
        port: port,
        isReady: isReady,
        serviceName: 'postgresql (systemd)',
      ),
    ];
  }

  static Future<List<PgServerInfo>> _detectLocalWindows() async {
    final result = await _runWithTimeout(
        'sc', ['query', 'type=', 'service', 'state=', 'active']);
    if (result == null || result.exitCode != 0) return [];

    final output = result.stdout.toString();
    final pgRegex =
        RegExp(r'SERVICE_NAME:\s*(postgresql\S*)', caseSensitive: false);
    final match = pgRegex.firstMatch(output);
    if (match == null) return [];

    final serviceName = match.group(1) ?? 'postgresql';
    const port = 5432;
    final isReady = await _checkPgReady(port);

    return [
      PgServerInfo(
        source: PgServerSource.local,
        port: port,
        isReady: isReady,
        serviceName: serviceName,
      ),
    ];
  }

  static Future<bool> _checkPgReady(int port) async {
    try {
      final pgReady = await pgIsReadyPath;
      final result = await Process.run(
        pgReady,
        ['-h', 'localhost', '-p', port.toString(), '-t', '1'],
        runInShell: true,
      ).timeout(const Duration(seconds: 3));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Docker Container Controls ──

  /// Start a Docker container
  static Future<bool> startContainer(String containerName) async {
    try {
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
          docker, ['start', containerName],
          runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Stop a Docker container
  static Future<bool> stopContainer(String containerName) async {
    try {
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
          docker, ['stop', containerName],
          runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Restart a Docker container
  static Future<bool> restartContainer(String containerName) async {
    try {
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
          docker, ['restart', containerName],
          runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Start local PostgreSQL service
  static Future<bool> startLocalService() async {
    try {
      if (PlatformService.isMacOS) {
        final brew = await PlatformService.brewPath;
        final result = await Process.run(
            brew, ['services', 'start', 'postgresql'],
            runInShell: true);
        return result.exitCode == 0;
      } else if (PlatformService.isLinux) {
        final result = await Process.run(
            'pkexec', ['systemctl', 'start', 'postgresql'],
            runInShell: true);
        return result.exitCode == 0;
      } else {
        final result = await Process.run(
            'net', ['start', 'postgresql'],
            runInShell: true);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  // ── Docker Project Init ──

  /// Generate a random password
  static String _generatePassword([int length = 32]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)])
        .join();
  }

  /// Initialize a PostgreSQL Docker project
  static Future<String> initProject({
    required String baseDir,
    required String dbUser,
    required String dbPassword,
    required int hostPort,
    required void Function(String line) onOutput,
  }) async {
    final projectDir = p.join(baseDir, 'postgresql');
    onOutput('[+] Creating PostgreSQL Docker project...');
    onOutput('[+] Directory: $projectDir');

    // Create directory
    final dir = Directory(projectDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Write docker-compose.yml
    onOutput('[+] Writing docker-compose.yml');
    await File(p.join(projectDir, 'docker-compose.yml'))
        .writeAsString(PostgresTemplates.dockerCompose());

    // Write .env
    onOutput('[+] Writing .env');
    await File(p.join(projectDir, '.env')).writeAsString(
        PostgresTemplates.envFile(
      user: dbUser,
      password: dbPassword,
      hostPort: hostPort,
    ));

    // Write postgresql.conf
    onOutput('[+] Writing postgresql.conf');
    await File(p.join(projectDir, 'postgresql.conf'))
        .writeAsString(PostgresTemplates.postgresqlConf());

    // Run docker compose up -d
    final docker = await PlatformService.dockerPath;
    onOutput('[+] Starting container...');
    final composeResult = await Process.run(
      docker,
      ['compose', 'up', '-d'],
      workingDirectory: projectDir,
      runInShell: true,
    );
    if (composeResult.exitCode == 0) {
      onOutput('[+] PostgreSQL container started successfully!');
      onOutput('[+] Connection: psql -h localhost -p $hostPort -U $dbUser');
    } else {
      final stderr = composeResult.stderr.toString().trim();
      if (stderr.isNotEmpty) onOutput('[WARN] $stderr');
      onOutput('[ERROR] Failed to start container (exit code ${composeResult.exitCode})');
    }

    return projectDir;
  }

  /// Default values for new project
  static String get defaultPassword => _generatePassword();
  static const defaultPort = 5432;
  static const defaultUser = 'odoo';

  // ── Client Install ──

  static const availableVersions = [17, 16, 15, 14];

  static Future<({String executable, List<String> args, String description})>
      installCommand({int? version}) async {
    if (PlatformService.isWindows) {
      final pkg = version != null
          ? 'PostgreSQL.PostgreSQL.$version'
          : 'PostgreSQL.PostgreSQL';
      return (
        executable: 'winget',
        args: [
          'install',
          pkg,
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install $pkg',
      );
    } else if (PlatformService.isMacOS) {
      final brew = await PlatformService.brewPath;
      return (
        executable: brew,
        args: ['install', 'libpq'],
        description: 'brew install libpq',
      );
    } else {
      return (
        executable: 'pkexec',
        args: [
          'bash',
          '-c',
          'apt update && apt install -y postgresql-client',
        ],
        description: 'apt install postgresql-client',
      );
    }
  }

  static Future<int> install(void Function(String line) onOutput, {int? version}) async {
    final cmd = await installCommand(version: version);
    onOutput('[+] Running: ${cmd.description}');
    onOutput('');

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      String lastLine = '';
      final stdoutDone =
          process.stdout.transform(utf8.decoder).listen((data) {
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

      final stderrDone =
          process.stderr.transform(utf8.decoder).listen((data) {
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
        onOutput('[+] PostgreSQL client tools installed successfully!');
        if (PlatformService.isWindows) {
          onOutput('');
          onOutput('[+] Note: This also installs PostgreSQL server.');
          onOutput('[+] If you only need client tools (for Docker), you can stop the local server:');
          onOutput('[+]   sc stop postgresql-x64-17');
          onOutput('[+]   sc config postgresql-x64-17 start=demand');
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
