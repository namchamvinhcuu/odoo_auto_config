import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

class OdooProjectsState {
  final List<ProjectInfo> projects;
  final bool gridView;

  const OdooProjectsState({
    this.projects = const [],
    this.gridView = true,
  });

  OdooProjectsState copyWith({
    List<ProjectInfo>? projects,
    bool? gridView,
  }) {
    return OdooProjectsState(
      projects: projects ?? this.projects,
      gridView: gridView ?? this.gridView,
    );
  }
}

class OdooProjectsNotifier extends AsyncNotifier<OdooProjectsState> {
  @override
  Future<OdooProjectsState> build() async {
    final gridView = await _loadViewPreference();
    final projects = await _loadProjects();
    return OdooProjectsState(projects: projects, gridView: gridView);
  }

  Future<List<ProjectInfo>> _loadProjects() async {
    final json = await StorageService.loadProjects();
    final projects = json.map((j) => ProjectInfo.fromJson(j)).toList();
    projects.sort((a, b) {
      if (a.favourite != b.favourite) return a.favourite ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return projects;
  }

  Future<bool> _loadViewPreference() async {
    final settings = await StorageService.loadSettings();
    return settings['gridView'] as bool? ?? true;
  }

  Future<void> reload() async {
    final current = state.valueOrNull;
    final projects = await _loadProjects();
    state = AsyncData(OdooProjectsState(
      projects: projects,
      gridView: current?.gridView ?? true,
    ));
  }

  Future<void> addProject(ProjectInfo project) async {
    await StorageService.addProject(project.toJson());
    await reload();
  }

  /// Returns conflict message if port conflict, null otherwise.
  Future<String?> checkPortConflict(ProjectInfo project) async {
    return StorageService.checkPortConflict(
        project.httpPort, project.longpollingPort, project.path);
  }

  Future<void> deleteProject(ProjectInfo project) async {
    // Cleanup nginx if configured
    if (project.hasNginx) {
      try {
        await NginxService.removeNginx(project.nginxSubdomain!);
      } catch (_) {}
    }
    await StorageService.removeProject(project.path);
    await reload();
  }

  Future<void> toggleFavourite(ProjectInfo project) async {
    final updated = project.copyWith(favourite: !project.favourite);
    await StorageService.removeProject(project.path);
    await StorageService.addProject(updated.toJson());
    await reload();
  }

  Future<void> toggleGridView() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final newGrid = !current.gridView;
    state = AsyncData(current.copyWith(gridView: newGrid));
    await StorageService.updateSettings((settings) {
      settings['gridView'] = newGrid;
    });
  }
}

final odooProjectsProvider =
    AsyncNotifierProvider<OdooProjectsNotifier, OdooProjectsState>(
        OdooProjectsNotifier.new);
