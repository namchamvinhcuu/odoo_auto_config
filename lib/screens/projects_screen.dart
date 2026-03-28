import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../models/project_info.dart';
import '../l10n/l10n_extension.dart';
import '../services/platform_service.dart';
import '../services/nginx_service.dart';
import '../services/storage_service.dart';
import '../widgets/nginx_setup_dialog.dart';
import 'quick_create_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  /// Shared grid view state across project screens, persisted in settings
  static bool gridView = true;
  static bool _loaded = false;

  static Future<void> loadViewPreference() async {
    if (_loaded) return;
    final settings = await StorageService.loadSettings();
    gridView = settings['gridView'] as bool? ?? true;
    _loaded = true;
  }

  static Future<void> saveViewPreference() async {
    final settings = await StorageService.loadSettings();
    settings['gridView'] = gridView;
    await StorageService.saveSettings(settings);
  }

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectInfo> _projects = [];
  List<ProjectInfo> _filtered = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  final Map<String, bool> _nginxStatus = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final json = await StorageService.loadProjects();
    final projects = json.map((j) => ProjectInfo.fromJson(j)).toList();
    projects.sort((a, b) {
      if (a.favourite != b.favourite) return a.favourite ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    // Check nginx status for all projects
    final nginx = await NginxService.loadSettings();
    final confDir = (nginx['confDir'] ?? '').toString();
    final status = <String, bool>{};
    if (confDir.isNotEmpty) {
      for (final p in projects) {
        status[p.path] = await NginxService.isNginxSetup(confDir, p.name);
      }
    }

    setState(() {
      _projects = projects;
      _nginxStatus.clear();
      _nginxStatus.addAll(status);
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    _filtered = q.isEmpty
        ? _projects
        : _projects.where((p) {
            return p.name.toLowerCase().contains(q) ||
                p.path.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q) ||
                p.httpPort.toString().contains(q);
          }).toList();
  }

  Future<void> _quickCreate() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => const QuickCreateDialog(),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _importProject() async {
    final result = await showDialog<ProjectInfo>(
      context: context,
      builder: (ctx) => const _ImportProjectDialog(),
    );
    if (result != null) {
      final conflict = await StorageService.checkPortConflict(
          result.httpPort, result.longpollingPort, result.path);
      if (conflict != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(conflict), backgroundColor: Colors.red),
        );
        return;
      }
      await StorageService.addProject(result.toJson());
      await _load();
    }
  }

  Future<void> _openInFileManager(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpen(path))),
        );
      }
    }
  }

  Future<void> _openInVscode(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Visual Studio Code', path]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'code', path], runInShell: true);
      } else {
        await Process.run('code', [path]);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpenVscode)),
        );
      }
    }
  }

  Future<void> _editProject(ProjectInfo project) async {
    final result = await showDialog<ProjectInfo>(
      context: context,
      builder: (ctx) => _ImportProjectDialog(existing: project),
    );
    if (result != null) {
      final conflict = await StorageService.checkPortConflict(
          result.httpPort, result.longpollingPort, result.path);
      if (conflict != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(conflict), backgroundColor: Colors.red),
        );
        return;
      }
      await StorageService.removeProject(project.path);
      await StorageService.addProject(result.toJson());
      await _load();
    }
  }

  Future<void> _setupNginx(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (suffix.isEmpty || (nginx['confDir'] ?? '').toString().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxNotConfigured)),
        );
      }
      return;
    }

    final result = await showDialog<({String subdomain, int? port})>(
      context: context,
      builder: (ctx) => NginxSetupDialog(
        initialSubdomain: NginxService.sanitizeSubdomain(proj.name),
        domainSuffix: suffix,
      ),
    );
    if (result == null) return;

    try {
      final domain = await NginxService.setupOdoo(
        subdomain: result.subdomain,
        httpPort: proj.httpPort,
        longpollingPort: proj.longpollingPort,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxSetupSuccess(domain))),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.nginxFailed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeNginx(ProjectInfo proj) async {
    final subdomain = NginxService.sanitizeSubdomain(proj.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.nginxRemove),
        content: Text(context.l10n.nginxConfirmRemove(proj.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(context.l10n.nginxRemove)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final nginx = await NginxService.loadSettings();
      final suffix = (nginx['domainSuffix'] ?? '').toString();
      await NginxService.removeNginx(subdomain);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.l10n.nginxRemoveSuccess('$subdomain$suffix'))),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.nginxFailed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleFavourite(ProjectInfo proj) async {
    final updated = proj.copyWith(favourite: !proj.favourite);
    await StorageService.removeProject(proj.path);
    await StorageService.addProject(updated.toJson());
    await _load();
  }

  Future<void> _remove(ProjectInfo project) async {
    bool deleteFiles = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.l10n.deleteProjectTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.deleteProjectConfirm(project.name)),
              const SizedBox(height: AppSpacing.xs),
              Text(project.path,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.sm,
                      color: Colors.grey.shade500)),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Checkbox(
                    value: deleteFiles,
                    onChanged: (v) =>
                        setDialogState(() => deleteFiles = v ?? false),
                  ),
                  Expanded(
                    child: Text(
                      context.l10n.alsoDeleteFromDisk,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: Text(context.l10n.delete)),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      if (deleteFiles) {
        try {
          final dir = Directory(project.path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.deletedPath(project.path))),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.failedToDelete(e.toString())),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      await StorageService.removeProject(project.path);
      await _load();
    }
  }

  // ── List View ──

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final proj = _filtered[index];
        final exists = Directory(proj.path).existsSync();

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      exists ? Icons.folder_special : Icons.folder_off,
                      color: exists ? Colors.deepPurple : Colors.grey,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        proj.name,
                        style: const TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      avatar: const Icon(Icons.lan, size: AppIconSize.sm),
                      label: Text(
                          context.l10n.projectHttpPort(proj.httpPort)),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Chip(
                      avatar: const Icon(Icons.sync, size: AppIconSize.sm),
                      label: Text(
                          context.l10n.projectLpPort(proj.longpollingPort)),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (proj.description.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Chip(
                          label: Text(proj.description,
                              overflow: TextOverflow.ellipsis),
                          avatar: const Icon(Icons.description,
                              size: AppIconSize.md),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  proj.path,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppFontSize.sm,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _toggleFavourite(proj),
                      icon: Icon(
                        proj.favourite ? Icons.star : Icons.star_border,
                        color: proj.favourite ? Colors.amber : null,
                      ),
                      tooltip: proj.favourite ? context.l10n.unfavourite : context.l10n.favourite,
                    ),
                    if (exists) ...[
                      IconButton(
                        onPressed: () => _openInVscode(proj.path),
                        icon: const Icon(Icons.code),
                        tooltip: context.l10n.openInVscode,
                      ),
                      IconButton(
                        onPressed: () => _openInFileManager(proj.path),
                        icon: const Icon(Icons.folder_open),
                        tooltip: context.l10n.openFolder,
                      ),
                    ],
                    IconButton(
                      onPressed: () => _editProject(proj),
                      icon: const Icon(Icons.edit),
                      tooltip: context.l10n.edit,
                    ),
                    IconButton(
                      onPressed: () => _nginxStatus[proj.path] == true
                          ? _removeNginx(proj)
                          : _setupNginx(proj),
                      icon: Icon(
                        Icons.dns,
                        color: _nginxStatus[proj.path] == true
                            ? Colors.green
                            : null,
                      ),
                      tooltip: _nginxStatus[proj.path] == true
                          ? context.l10n.nginxRemove
                          : context.l10n.nginxSetup,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _remove(proj),
                      icon: const Icon(Icons.delete),
                      color: Colors.red,
                      tooltip: context.l10n.removeFromList,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Grid View ──

  int _gridCrossAxisCount(double width) {
    if (width >= 1100) return 5;
    if (width >= 800) return 4;
    return 3;
  }

  Widget _buildGridView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridCrossAxisCount(constraints.maxWidth);
        final cellWidth =
            (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
        final nameSize = cellWidth >= 200 ? AppFontSize.xl : AppFontSize.lg;
        final portSize = cellWidth >= 200 ? AppFontSize.sm : AppFontSize.xs;
        final btnSize = cellWidth * 0.12;
        final btnBox = cellWidth * 0.18;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1,
          ),
          itemCount: _filtered.length,
          itemBuilder: (context, index) {
            final proj = _filtered[index];
            final exists = Directory(proj.path).existsSync();

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: proj.description.isNotEmpty ? proj.description : proj.path,
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  onTap: exists ? () => _openInVscode(proj.path) : null,
                  onSecondaryTapDown: (details) =>
                      _showGridContextMenu(details.globalPosition, proj, exists),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          onPressed: () => _toggleFavourite(proj),
                          icon: Icon(
                            proj.favourite ? Icons.star : Icons.star_border,
                            size: AppIconSize.lg,
                            color: proj.favourite ? Colors.amber : Colors.grey.shade600,
                          ),
                          tooltip: proj.favourite ? context.l10n.unfavourite : context.l10n.favourite,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                      const Spacer(),
                      // Odoo badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.15),
                          borderRadius: AppRadius.mediumBorderRadius,
                        ),
                        child: Text(
                          'Odoo',
                          style: TextStyle(
                            fontSize: portSize,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Project name
                      Text(
                        proj.name,
                        style: TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Ports info
                      Text(
                        '${proj.httpPort} / ${proj.longpollingPort}',
                        style: TextStyle(
                          fontSize: portSize,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      // Quick actions
                      if (exists)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: AppSpacing.lg,
                          children: [
                            _gridBtn(
                              icon: Icons.code,
                              tooltip: context.l10n.openInVscode,
                              onPressed: () => _openInVscode(proj.path),
                              iconSize: btnSize,
                              boxSize: btnBox,
                            ),
                            _gridBtn(
                              icon: Icons.folder_open,
                              tooltip: context.l10n.openFolder,
                              onPressed: () => _openInFileManager(proj.path),
                              iconSize: btnSize,
                              boxSize: btnBox,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  void _showGridContextMenu(
      Offset position, ProjectInfo proj, bool exists) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'favourite',
          child: Row(
            children: [
              Icon(proj.favourite ? Icons.star : Icons.star_border,
                  size: AppIconSize.md,
                  color: proj.favourite ? Colors.amber : null),
              const SizedBox(width: AppSpacing.sm),
              Text(proj.favourite ? context.l10n.unfavourite : context.l10n.favourite),
            ],
          ),
        ),
        if (exists)
          PopupMenuItem(
            value: 'vscode',
            child: Row(
              children: [
                const Icon(Icons.code, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.openInVscode),
              ],
            ),
          ),
        if (exists)
          PopupMenuItem(
            value: 'folder',
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.openFolder),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'nginx',
          child: Row(
            children: [
              Icon(Icons.dns, size: AppIconSize.md,
                  color: _nginxStatus[proj.path] == true ? Colors.green : null),
              const SizedBox(width: AppSpacing.sm),
              Text(_nginxStatus[proj.path] == true
                  ? context.l10n.nginxRemove
                  : context.l10n.nginxSetup),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, size: AppIconSize.md),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.edit),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, size: AppIconSize.md, color: Colors.red),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.removeFromList,
                  style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
    if (result == null) return;
    switch (result) {
      case 'favourite':
        _toggleFavourite(proj);
      case 'vscode':
        _openInVscode(proj.path);
      case 'folder':
        _openInFileManager(proj.path);
      case 'nginx':
        _nginxStatus[proj.path] == true
            ? _removeNginx(proj)
            : _setupNginx(proj);
      case 'edit':
        _editProject(proj);
      case 'delete':
        _remove(proj);
    }
  }

  Widget _gridBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required double iconSize,
    required double boxSize,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: boxSize, minHeight: boxSize),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              const Icon(Icons.folder_special, size: AppIconSize.xl),
              Text(context.l10n.projectsTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: AppSpacing.xxxl),
              FilledButton.icon(
                onPressed: _quickCreate,
                icon: const Icon(Icons.rocket_launch),
                label: Text(context.l10n.create),
              ),
              FilledButton.tonalIcon(
                onPressed: _importProject,
                icon: const Icon(Icons.download),
                label: Text(context.l10n.import_),
              ),
              IconButton.filled(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.refresh,
              ),
              IconButton(
                onPressed: () {
                  setState(() => ProjectsScreen.gridView = !ProjectsScreen.gridView);
                  ProjectsScreen.saveViewPreference();
                },
                icon: Icon(ProjectsScreen.gridView ? Icons.view_list : Icons.grid_view),
                tooltip: ProjectsScreen.gridView
                    ? context.l10n.wsViewList
                    : context.l10n.wsViewGrid,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.projectsSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: context.l10n.projectsSearchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _applyFilter());
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() => _applyFilter()),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_projects.isEmpty)
            Expanded(
              child: Center(child: Text(context.l10n.projectsEmpty)),
            )
          else if (_filtered.isEmpty)
            Expanded(
              child: Center(child: Text(context.l10n.projectsNoMatch)),
            )
          else
            Expanded(
              child: ProjectsScreen.gridView ? _buildGridView() : _buildListView(),
            ),
        ],
      ),
    );
  }
}

// ── Import Project Dialog ──

class _ImportProjectDialog extends StatefulWidget {
  final ProjectInfo? existing;

  const _ImportProjectDialog({this.existing});

  @override
  State<_ImportProjectDialog> createState() => _ImportProjectDialogState();
}

class _ImportProjectDialogState extends State<_ImportProjectDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _httpPortController;
  late final TextEditingController _lpPortController;
  late String _projectPath;
  late String _description;
  bool _autoDetected = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _httpPortController =
        TextEditingController(text: '${e?.httpPort ?? 8069}');
    _lpPortController =
        TextEditingController(text: '${e?.longpollingPort ?? 8072}');
    _projectPath = e?.path ?? '';
    _description = e?.description ?? '';
  }

  Future<void> _pickDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
        dialogTitle: context.l10n.selectProjectDirectory,
      );
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: context.l10n.selectProjectDirectory,
      );
    }
    if (path == null) return;

    setState(() {
      _projectPath = path!;
      _nameController.text = path.split('/').last.split('\\').last;
    });

    // Try auto-detect ports from odoo.conf
    await _autoDetectFromConf(path);
  }

  Future<void> _autoDetectFromConf(String projectPath) async {
    final confPaths = [
      p.join(projectPath, 'odoo.conf'),
      p.join(projectPath, 'config', 'odoo.conf'),
    ];

    for (final confPath in confPaths) {
      final file = File(confPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final httpMatch =
            RegExp(r'http_port\s*=\s*(\d+)').firstMatch(content);
        final lpMatch =
            RegExp(r'longpolling_port\s*=\s*(\d+)').firstMatch(content);

        setState(() {
          if (httpMatch != null) {
            _httpPortController.text = httpMatch.group(1)!;
          }
          if (lpMatch != null) {
            _lpPortController.text = lpMatch.group(1)!;
          }
          _autoDetected = true;
        });
        return;
      }
    }
  }

  void _save() {
    if (_projectPath.isEmpty || _nameController.text.isEmpty) return;

    final project = ProjectInfo(
      name: _nameController.text.trim(),
      path: _projectPath,
      description: _description,
      httpPort: int.tryParse(_httpPortController.text) ?? 8069,
      longpollingPort: int.tryParse(_lpPortController.text) ?? 8072,
      createdAt: DateTime.now().toIso8601String(),
    );

    Navigator.pop(context, project);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _httpPortController.dispose();
    _lpPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null
          ? context.l10n.editProject
          : context.l10n.importExistingProject),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Project directory
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _projectPath),
                      decoration: InputDecoration(
                        labelText: context.l10n.projectDirectory,
                        hintText: context.l10n.browseToSelect,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _pickDir,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),

              if (_autoDetected) ...[
                const SizedBox(height: AppSpacing.sm),
                Card(
                  color: Colors.green.withValues(alpha: 0.1),
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high,
                            color: Colors.green, size: AppIconSize.md),
                        SizedBox(width: AppSpacing.sm),
                        Text(context.l10n.portsAutoDetected),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),

              // Project name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.projectName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Profile label (optional)
              TextField(
                controller: TextEditingController(text: _description),
                onChanged: (v) => _description = v,
                decoration: InputDecoration(
                  labelText: context.l10n.descriptionOptional,
                  hintText: context.l10n.descriptionHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Ports
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _httpPortController,
                      decoration: InputDecoration(
                        labelText: context.l10n.httpPort,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: TextField(
                      controller: _lpPortController,
                      decoration: InputDecoration(
                        labelText: context.l10n.longpollingPort,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel)),
        FilledButton(
          onPressed: (_projectPath.isNotEmpty &&
                  _nameController.text.isNotEmpty)
              ? _save
              : null,
          child: Text(widget.existing != null
              ? context.l10n.save
              : context.l10n.import_),
        ),
      ],
    );
  }
}
