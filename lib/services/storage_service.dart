import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class StorageService {
  static const _configFileName = 'odoo_auto_config.json';

  /// Serialize all read-modify-write operations to prevent race conditions.
  /// Without this lock, concurrent saves (e.g. saveSettings + saveWorkspaces)
  /// can overwrite each other's data — causing nginx config, git accounts, etc.
  /// to be lost.
  static Future<void> _lock = Future.value();

  static Future<T> _synchronized<T>(Future<T> Function() fn) {
    final prev = _lock;
    final completer = Completer<T>();
    _lock = completer.future.then((_) {}, onError: (_) {});
    () async {
      await prev;
      try {
        completer.complete(await fn());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    }();
    return completer.future;
  }

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
      List<Map<String, dynamic>> venvs) =>
    _synchronized(() async {
      final config = await _readConfig();
      config['registered_venvs'] = venvs;
      await _writeConfig(config);
    });

  static Future<void> addRegisteredVenv(Map<String, dynamic> venv) =>
    _synchronized(() async {
      final config = await _readConfig();
      final venvs = (config['registered_venvs'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      venvs.removeWhere((v) => v['path'] == venv['path']);
      venvs.add(venv);
      config['registered_venvs'] = venvs;
      await _writeConfig(config);
    });

  static Future<void> removeRegisteredVenv(String path) =>
    _synchronized(() async {
      final config = await _readConfig();
      final venvs = (config['registered_venvs'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      venvs.removeWhere((v) => v['path'] == path);
      config['registered_venvs'] = venvs;
      await _writeConfig(config);
    });

  // ── Profiles ──

  static Future<List<Map<String, dynamic>>> loadProfiles() async {
    final config = await _readConfig();
    final list = config['profiles'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveProfiles(
      List<Map<String, dynamic>> profiles) =>
    _synchronized(() async {
      final config = await _readConfig();
      config['profiles'] = profiles;
      await _writeConfig(config);
    });

  static Future<void> addOrUpdateProfile(Map<String, dynamic> profile) =>
    _synchronized(() async {
      final config = await _readConfig();
      final profiles = (config['profiles'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      profiles.removeWhere((p) => p['id'] == profile['id']);
      profiles.add(profile);
      config['profiles'] = profiles;
      await _writeConfig(config);
    });

  static Future<void> removeProfile(String id) =>
    _synchronized(() async {
      final config = await _readConfig();
      final profiles = (config['profiles'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      profiles.removeWhere((p) => p['id'] == id);
      config['profiles'] = profiles;
      await _writeConfig(config);
    });

  // ── Projects ──

  static Future<List<Map<String, dynamic>>> loadProjects() async {
    final config = await _readConfig();
    final list = config['projects'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveProjects(
      List<Map<String, dynamic>> projects) =>
    _synchronized(() async {
      final config = await _readConfig();
      config['projects'] = projects;
      await _writeConfig(config);
    });

  static Future<void> addProject(Map<String, dynamic> project) =>
    _synchronized(() async {
      final config = await _readConfig();
      final projects = (config['projects'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      projects.removeWhere((p) => p['path'] == project['path']);
      projects.add(project);
      config['projects'] = projects;
      await _writeConfig(config);
    });

  static Future<void> removeProject(String path) =>
    _synchronized(() async {
      final config = await _readConfig();
      final projects = (config['projects'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      projects.removeWhere((p) => p['path'] == path);
      config['projects'] = projects;
      await _writeConfig(config);
    });

  // ── Workspaces ──

  static Future<List<Map<String, dynamic>>> loadWorkspaces() async {
    final config = await _readConfig();
    final list = config['workspaces'] as List<dynamic>?;
    return list?.cast<Map<String, dynamic>>() ?? [];
  }

  static Future<void> saveWorkspaces(
      List<Map<String, dynamic>> workspaces) =>
    _synchronized(() async {
      final config = await _readConfig();
      config['workspaces'] = workspaces;
      await _writeConfig(config);
    });

  static Future<void> addWorkspace(Map<String, dynamic> workspace) =>
    _synchronized(() async {
      final config = await _readConfig();
      final workspaces = (config['workspaces'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      workspaces.removeWhere((w) => w['path'] == workspace['path']);
      workspaces.add(workspace);
      config['workspaces'] = workspaces;
      await _writeConfig(config);
    });

  static Future<void> removeWorkspace(String path) =>
    _synchronized(() async {
      final config = await _readConfig();
      final workspaces = (config['workspaces'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      workspaces.removeWhere((w) => w['path'] == path);
      config['workspaces'] = workspaces;
      await _writeConfig(config);
    });

  // ── Settings ──

  static Future<Map<String, dynamic>> loadSettings() async {
    final config = await _readConfig();
    return (config['settings'] as Map<String, dynamic>?) ?? {};
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) =>
    _synchronized(() async {
      final config = await _readConfig();
      config['settings'] = settings;
      await _writeConfig(config);
    });

  /// Atomic read-modify-write for settings. Prevents race conditions when
  /// multiple providers update different keys concurrently.
  /// The [update] callback receives the current settings and should modify
  /// the map in-place (add/change keys).
  static Future<void> updateSettings(
      void Function(Map<String, dynamic> settings) update) =>
    _synchronized(() async {
      final config = await _readConfig();
      final settings = (config['settings'] as Map<String, dynamic>?) ?? {};
      update(settings);
      config['settings'] = settings;
      await _writeConfig(config);
    });

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
