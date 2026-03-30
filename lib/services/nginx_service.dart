import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/command_result.dart';
import '../templates/nginx_templates.dart';
import 'command_runner.dart';
import 'platform_service.dart';
import 'storage_service.dart';

class NginxService {
  // ── Init project structure ──

  static Future<bool> isMkcertAvailable() async {
    try {
      final mkcert = await PlatformService.mkcertPath;
      final result =
          await Process.run(mkcert, ['-version'], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static ({String executable, List<String> args, String description})
      mkcertInstallCommand() {
    if (Platform.isWindows) {
      return (
        executable: 'winget',
        args: [
          'install',
          'FiloSottile.mkcert',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install FiloSottile.mkcert',
      );
    } else if (Platform.isMacOS) {
      return (
        executable: 'brew',
        args: ['install', 'mkcert'],
        description: 'brew install mkcert',
      );
    } else {
      return (
        executable: 'pkexec',
        args: ['apt', 'install', '-y', 'mkcert'],
        description: 'pkexec apt install -y mkcert',
      );
    }
  }

  static Future<int> installMkcert(void Function(String line) onOutput) async {
    final cmd = mkcertInstallCommand();
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
        onOutput('[+] mkcert installed successfully!');
        // Install CA
        onOutput('[+] Installing local CA...');
        final mkcert = await PlatformService.mkcertPath;
        await CommandRunner.run(mkcert, ['-install']);
        onOutput('[+] Done!');
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

  static Future<String> initProject({
    required String baseDir,
    required String folderName,
    required String domain,
    required void Function(String line) onOutput,
  }) async {
    final projectDir = p.join(baseDir, folderName);
    final confDir = p.join(projectDir, 'conf.d');
    final certsDir = p.join(projectDir, 'certs');

    // Create directories
    onOutput('[+] Creating directories...');
    await Directory(confDir).create(recursive: true);
    await Directory(certsDir).create(recursive: true);
    onOutput('[+] Created: $confDir');
    onOutput('[+] Created: $certsDir');

    // Strip leading dot from domain if present
    final cleanDomain = domain.startsWith('.') ? domain.substring(1) : domain;

    // Install mkcert CA first (required before generating certs)
    final mkcert = await PlatformService.mkcertPath;
    onOutput('');
    onOutput('[+] Installing mkcert local CA...');
    final caResult = await CommandRunner.run(mkcert, ['-install']);
    if (caResult.exitCode != 0) {
      onOutput('[WARN] mkcert CA install: ${caResult.stderr}');
    } else {
      onOutput('[+] Local CA installed');
    }

    // Generate SSL certs with mkcert
    onOutput('');
    onOutput('[+] Generating SSL certificates with mkcert...');
    final certName = '$cleanDomain+4';
    final mkcertResult = await CommandRunner.run(mkcert, [
      '-cert-file',
      p.join(certsDir, '$certName.pem'),
      '-key-file',
      p.join(certsDir, '$certName-key.pem'),
      cleanDomain,
      '*.$cleanDomain',
      'localhost',
      '127.0.0.1',
      '::1',
    ]);
    if (mkcertResult.exitCode != 0) {
      onOutput('[ERROR] mkcert failed: ${mkcertResult.stderr}');
      throw Exception('mkcert failed: ${mkcertResult.stderr}');
    }
    onOutput('[+] SSL certificates generated');

    // Linux uses host network; Windows/macOS use port mapping + host.docker.internal
    final useHostNetwork = Platform.isLinux;

    // Write nginx.conf
    onOutput('');
    onOutput('[+] Writing nginx.conf...');
    final nginxConf = NginxTemplates.nginxConf(
      certFile: '/etc/nginx/certs/$certName.pem',
      certKeyFile: '/etc/nginx/certs/$certName-key.pem',
    );
    await File(p.join(projectDir, 'nginx.conf')).writeAsString(nginxConf);

    // Write docker-compose.yml
    onOutput('[+] Writing docker-compose.yml...');
    final dockerCompose =
        NginxTemplates.dockerCompose(useHostNetwork: useHostNetwork);
    await File(p.join(projectDir, 'docker-compose.yml'))
        .writeAsString(dockerCompose);

    // Write .gitignore
    await File(p.join(projectDir, '.gitignore'))
        .writeAsString('certs/\n');

    onOutput('');
    onOutput('[+] Nginx project created at: $projectDir');
    onOutput('[+] Next: cd $folderName && docker compose up -d');

    return projectDir;
  }

  // ── Port check ──

  /// Check if a port is in use and return info about the process
  static Future<({bool inUse, String? process, int? pid})> checkPort(
      int port) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
            'netstat', ['-ano', '-p', 'TCP'], runInShell: true);
        if (result.exitCode == 0) {
          for (final line in result.stdout.toString().split('\n')) {
            if (line.contains(':$port ') && line.contains('LISTENING')) {
              final parts = line.trim().split(RegExp(r'\s+'));
              final pid = int.tryParse(parts.last);
              String? processName;
              if (pid != null) {
                final taskResult = await Process.run(
                    'tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV'],
                    runInShell: true);
                if (taskResult.exitCode == 0) {
                  final lines = taskResult.stdout.toString().split('\n');
                  if (lines.length > 1) {
                    processName = lines[1].split(',').first.replaceAll('"', '');
                  }
                }
              }
              return (inUse: true, process: processName, pid: pid);
            }
          }
        }
      } else {
        // macOS / Linux
        final result = await Process.run(
            'lsof', ['-i', ':$port', '-sTCP:LISTEN', '-t'],
            runInShell: true);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          final pid =
              int.tryParse(result.stdout.toString().trim().split('\n').first);
          String? processName;
          if (pid != null) {
            final psResult = await Process.run(
                'ps', ['-p', '$pid', '-o', 'comm='], runInShell: true);
            if (psResult.exitCode == 0) {
              processName = psResult.stdout.toString().trim();
            }
          }
          return (inUse: true, process: processName, pid: pid);
        }
      }
    } catch (_) {}
    return (inUse: false, process: null, pid: null);
  }

  /// Check if a docker container is running with host network
  static Future<bool> isDockerContainerRunning(String containerName) async {
    try {
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
          docker,
          ['inspect', '--format', '{{.State.Running}}', containerName],
          runInShell: true);
      return result.exitCode == 0 &&
          result.stdout.toString().trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Check both port 80 and 443, return list of conflicts with source detection
  static Future<
      ({
        List<({int port, String? process, int? pid, String source})> conflicts,
        bool dockerNginxRunning,
      })> checkNginxPorts(String containerName) async {
    final dockerRunning = await isDockerContainerRunning(containerName);

    final conflicts =
        <({int port, String? process, int? pid, String source})>[];
    for (final port in [80, 443]) {
      final result = await checkPort(port);
      if (result.inUse) {
        // Determine source: if docker nginx is running and process is docker runtime
        final processName = (result.process ?? '').toLowerCase();
        final isDocker = dockerRunning &&
            (processName.contains('docker') ||
                processName.contains('orbstack') ||
                processName.contains('com.docker') ||
                processName.contains('vpnkit') ||
                processName.contains('containerd'));

        conflicts.add((
          port: port,
          process: result.process,
          pid: result.pid,
          source: isDocker ? 'docker:$containerName' : 'local',
        ));
      }
    }
    return (conflicts: conflicts, dockerNginxRunning: dockerRunning);
  }

  /// Kill a process by PID (elevated on macOS/Linux)
  static Future<CommandResult> killProcess(int pid) async {
    if (Platform.isWindows) {
      return CommandRunner.run('taskkill', ['/F', '/PID', '$pid']);
    } else if (Platform.isMacOS) {
      return CommandRunner.run('osascript', [
        '-e',
        'do shell script "kill -9 $pid" with administrator privileges',
      ]);
    } else {
      return CommandRunner.run('pkexec', ['kill', '-9', '$pid']);
    }
  }

  /// Check if a process name looks like local nginx
  static bool isLocalNginx(String? processName) {
    if (processName == null) return false;
    final lower = processName.toLowerCase();
    return lower.contains('nginx') &&
        !lower.contains('docker') &&
        !lower.contains('orbstack') &&
        !lower.contains('containerd');
  }

  // ── Settings ──

  static Future<Map<String, dynamic>> loadSettings() async {
    final settings = await StorageService.loadSettings();
    return (settings['nginx'] as Map<String, dynamic>?) ?? {};
  }

  static Future<void> saveSettings(Map<String, dynamic> nginx) async {
    final settings = await StorageService.loadSettings();
    settings['nginx'] = nginx;
    await StorageService.saveSettings(settings);
  }

  // ── Domain & file helpers ──

  static String getDomain(String projectName, String domainSuffix) {
    final sanitized = projectName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$sanitized$domainSuffix';
  }

  static String getConfFileName(String projectName) {
    final sanitized = projectName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return '$sanitized.conf';
  }

  // ── Check status ──

  static Future<bool> isNginxSetup(String confDir, String subdomain) async {
    final file = File(p.join(confDir, getConfFileName(subdomain)));
    return file.exists();
  }

  /// List all existing subdomain conf files in confDir
  static Future<Set<String>> getExistingSubdomains(String confDir) async {
    final dir = Directory(confDir);
    if (!await dir.exists()) return {};
    final result = <String>{};
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.conf')) {
        result.add(p.basenameWithoutExtension(entity.path));
      }
    }
    return result;
  }

  /// Get all ports currently proxied by nginx (from both Odoo + Other projects)
  static Future<Map<int, String>> getUsedPorts() async {
    final usedPorts = <int, String>{};

    // Odoo projects: httpPort + longpollingPort for projects with nginx active
    final nginx = await loadSettings();
    final confDir = (nginx['confDir'] ?? '').toString();
    if (confDir.isEmpty) return usedPorts;

    final projects = await StorageService.loadProjects();
    for (final p in projects) {
      final name = (p['name'] ?? '').toString();
      if (await isNginxSetup(confDir, sanitizeSubdomain(name))) {
        final http = p['httpPort'] as int? ?? 0;
        final lp = p['longpollingPort'] as int? ?? 0;
        if (http > 0) usedPorts[http] = name;
        if (lp > 0) usedPorts[lp] = name;
      }
    }

    // Other projects: port for workspaces with nginx active
    final workspaces = await StorageService.loadWorkspaces();
    for (final w in workspaces) {
      final name = (w['name'] ?? '').toString();
      if (await isNginxSetup(confDir, sanitizeSubdomain(name))) {
        final port = w['port'] as int? ?? 0;
        if (port > 0) usedPorts[port] = name;
      }
    }

    return usedPorts;
  }

  /// Sanitize project name to a valid subdomain
  static String sanitizeSubdomain(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  // ── Setup ──

  static Future<String> setupOdoo({
    required String subdomain,
    required int httpPort,
    required int longpollingPort,
  }) async {
    final nginx = await loadSettings();
    _validateSettings(nginx);

    final confDir = nginx['confDir'] as String;
    final suffix = nginx['domainSuffix'] as String;
    final container = nginx['containerName'] as String;
    final domain = '$subdomain$suffix';

    final content = NginxTemplates.odooConf(
      domain: domain,
      httpPort: httpPort,
      longpollingPort: longpollingPort,
      useHostNetwork: Platform.isLinux,
    );

    await _writeConf(confDir, getConfFileName(subdomain), content);
    await _addHostsEntry(domain);
    await _reloadNginx(container);

    return domain;
  }

  static Future<String> setupGeneric({
    required String subdomain,
    required int port,
  }) async {
    final nginx = await loadSettings();
    _validateSettings(nginx);

    final confDir = nginx['confDir'] as String;
    final suffix = nginx['domainSuffix'] as String;
    final container = nginx['containerName'] as String;
    final domain = '$subdomain$suffix';

    final content = NginxTemplates.genericConf(
      domain: domain,
      port: port,
      useHostNetwork: Platform.isLinux,
    );

    await _writeConf(confDir, getConfFileName(subdomain), content);
    await _addHostsEntry(domain);
    await _reloadNginx(container);

    return domain;
  }

  // ── Remove ──

  static Future<void> removeNginx(String subdomain) async {
    final nginx = await loadSettings();
    _validateSettings(nginx);

    final confDir = nginx['confDir'] as String;
    final suffix = nginx['domainSuffix'] as String;
    final container = nginx['containerName'] as String;
    final domain = '$subdomain$suffix';

    await _removeConf(confDir, getConfFileName(subdomain));
    await _removeHostsEntry(domain);
    await _reloadNginx(container);
  }

  // ── Private helpers ──

  static void _validateSettings(Map<String, dynamic> nginx) {
    if (nginx['confDir'] == null ||
        nginx['domainSuffix'] == null ||
        nginx['containerName'] == null ||
        (nginx['confDir'] as String).isEmpty) {
      throw Exception('Nginx settings not configured');
    }
  }

  static Future<void> _writeConf(
      String confDir, String fileName, String content) async {
    final file = File(p.join(confDir, fileName));
    await file.writeAsString(content);
  }

  static Future<void> _removeConf(String confDir, String fileName) async {
    final file = File(p.join(confDir, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<CommandResult> _reloadNginx(String containerName) async {
    final docker = await PlatformService.dockerPath;
    return CommandRunner.run(
        docker, ['exec', containerName, 'nginx', '-s', 'reload']);
  }

  static String get _hostsPath {
    if (Platform.isWindows) {
      return r'C:\Windows\System32\drivers\etc\hosts';
    }
    return '/etc/hosts';
  }

  static Future<void> _addHostsEntry(String domain) async {
    final hostsFile = File(_hostsPath);
    final content = await hostsFile.readAsString();
    if (content.contains(domain)) return;

    final entry = '127.0.0.1\t$domain';

    if (Platform.isMacOS) {
      await CommandRunner.run('osascript', [
        '-e',
        'do shell script "echo \'$entry\' >> /etc/hosts" with administrator privileges',
      ]);
    } else if (Platform.isLinux) {
      await CommandRunner.run('pkexec', [
        'bash',
        '-c',
        'echo "$entry" >> /etc/hosts',
      ]);
    } else if (Platform.isWindows) {
      final tempDir = Platform.environment['TEMP'] ?? r'C:\Windows\Temp';
      final script = File(p.join(tempDir, 'odoo_hosts_add.ps1'));
      await script.writeAsString(
        'Add-Content -Path "C:\\Windows\\System32\\drivers\\etc\\hosts" -Value "$entry" -Encoding UTF8',
      );
      try {
        await CommandRunner.run('powershell', [
          '-Command',
          'Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "${script.path}"',
        ]);
      } finally {
        try { await script.delete(); } catch (_) {}
      }
    }
  }

  static Future<void> _removeHostsEntry(String domain) async {
    if (Platform.isMacOS) {
      await CommandRunner.run('osascript', [
        '-e',
        'do shell script "sed -i \'\' \'/$domain/d\' /etc/hosts" with administrator privileges',
      ]);
    } else if (Platform.isLinux) {
      await CommandRunner.run('pkexec', [
        'bash',
        '-c',
        'sed -i \'/$domain/d\' /etc/hosts',
      ]);
    } else if (Platform.isWindows) {
      final tempDir = Platform.environment['TEMP'] ?? r'C:\Windows\Temp';
      final script = File(p.join(tempDir, 'odoo_hosts_remove.ps1'));
      const hp = r'C:\Windows\System32\drivers\etc\hosts';
      await script.writeAsString(
        '(Get-Content "$hp") | Where-Object { \$_ -notmatch "$domain" } | Set-Content "$hp" -Encoding UTF8',
      );
      try {
        await CommandRunner.run('powershell', [
          '-Command',
          'Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "${script.path}"',
        ]);
      } finally {
        try { await script.delete(); } catch (_) {}
      }
    }
  }
}
