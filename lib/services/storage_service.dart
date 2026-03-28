import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class StorageService {
  static const _configFileName = 'odoo_auto_config.json';

  static String get _configPath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, '.config', 'odoo_auto_config', _configFileName);
  }

  static Future<Map<String, dynamic>> _readConfig() async {
    final file = File(_configPath);
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    if (content.isEmpty) return {};
    return jsonDecode(content) as Map<String, dynamic>;
  }

  static Future<void> _writeConfig(Map<String, dynamic> config) async {
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  // ── Registered Venvs ──

  static Future<List<Map<String, dynamic>>> loadRegisteredVenvs() async {
    final config = await _readConfig();
    final list = config['registered_venvs'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveRegisteredVenvs(
      List<Map<String, dynamic>> venvs) async {
    final config = await _readConfig();
    config['registered_venvs'] = venvs;
    await _writeConfig(config);
  }

  static Future<void> addRegisteredVenv(Map<String, dynamic> venv) async {
    final venvs = await loadRegisteredVenvs();
    // Avoid duplicates by path
    venvs.removeWhere((v) => v['path'] == venv['path']);
    venvs.add(venv);
    await saveRegisteredVenvs(venvs);
  }

  static Future<void> removeRegisteredVenv(String path) async {
    final venvs = await loadRegisteredVenvs();
    venvs.removeWhere((v) => v['path'] == path);
    await saveRegisteredVenvs(venvs);
  }

  // ── Profiles ──

  static Future<List<Map<String, dynamic>>> loadProfiles() async {
    final config = await _readConfig();
    final list = config['profiles'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveProfiles(List<Map<String, dynamic>> profiles) async {
    final config = await _readConfig();
    config['profiles'] = profiles;
    await _writeConfig(config);
  }

  static Future<void> addOrUpdateProfile(Map<String, dynamic> profile) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p['id'] == profile['id']);
    profiles.add(profile);
    await saveProfiles(profiles);
  }

  static Future<void> removeProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((p) => p['id'] == id);
    await saveProfiles(profiles);
  }

  // ── Projects ──

  static Future<List<Map<String, dynamic>>> loadProjects() async {
    final config = await _readConfig();
    final list = config['projects'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveProjects(
      List<Map<String, dynamic>> projects) async {
    final config = await _readConfig();
    config['projects'] = projects;
    await _writeConfig(config);
  }

  static Future<void> addProject(Map<String, dynamic> project) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p['path'] == project['path']);
    projects.add(project);
    await saveProjects(projects);
  }

  static Future<void> removeProject(String path) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p['path'] == path);
    await saveProjects(projects);
  }

  // ── Workspaces ──

  static Future<List<Map<String, dynamic>>> loadWorkspaces() async {
    final config = await _readConfig();
    final list = config['workspaces'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveWorkspaces(
      List<Map<String, dynamic>> workspaces) async {
    final config = await _readConfig();
    config['workspaces'] = workspaces;
    await _writeConfig(config);
  }

  static Future<void> addWorkspace(Map<String, dynamic> workspace) async {
    final workspaces = await loadWorkspaces();
    workspaces.removeWhere((w) => w['path'] == workspace['path']);
    workspaces.add(workspace);
    await saveWorkspaces(workspaces);
  }

  static Future<void> removeWorkspace(String path) async {
    final workspaces = await loadWorkspaces();
    workspaces.removeWhere((w) => w['path'] == path);
    await saveWorkspaces(workspaces);
  }

  // ── Settings ──

  static Future<Map<String, dynamic>> loadSettings() async {
    final config = await _readConfig();
    return (config['settings'] as Map<String, dynamic>?) ?? {};
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final config = await _readConfig();
    config['settings'] = settings;
    await _writeConfig(config);
  }

  /// Check if a port is already used by another project
  static Future<String?> checkPortConflict(
      int httpPort, int longpollingPort, String? excludePath) async {
    final projects = await loadProjects();
    for (final p in projects) {
      if (excludePath != null && p['path'] == excludePath) continue;
      final name = p['name'] ?? '';
      if (p['httpPort'] == httpPort) {
        return 'HTTP port $httpPort is already used by project "$name"';
      }
      if (p['longpollingPort'] == longpollingPort) {
        return 'Longpolling port $longpollingPort is already used by project "$name"';
      }
      if (p['httpPort'] == longpollingPort) {
        return 'Longpolling port $longpollingPort conflicts with HTTP port of project "$name"';
      }
      if (p['longpollingPort'] == httpPort) {
        return 'HTTP port $httpPort conflicts with longpolling port of project "$name"';
      }
    }
    return null;
  }
}
