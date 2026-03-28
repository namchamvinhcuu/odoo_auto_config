import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/command_result.dart';
import '../templates/nginx_templates.dart';
import 'command_runner.dart';
import 'storage_service.dart';

class NginxService {
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
    return CommandRunner.run(
        'docker', ['exec', containerName, 'nginx', '-s', 'reload']);
  }

  static Future<void> _addHostsEntry(String domain) async {
    // Check if already exists
    final hostsFile = File('/etc/hosts');
    final content = await hostsFile.readAsString();
    if (content.contains(domain)) return;

    if (Platform.isMacOS) {
      await CommandRunner.run('osascript', [
        '-e',
        'do shell script "echo \'127.0.0.1\t$domain\' >> /etc/hosts" with administrator privileges',
      ]);
    } else if (Platform.isLinux) {
      await CommandRunner.run('pkexec', [
        'bash',
        '-c',
        'echo "127.0.0.1\t$domain" >> /etc/hosts',
      ]);
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
    }
  }
}
