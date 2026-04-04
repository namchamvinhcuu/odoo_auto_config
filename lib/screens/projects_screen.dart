import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../models/project_info.dart';
import '../l10n/l10n_extension.dart';
import '../services/platform_service.dart';
import '../services/nginx_service.dart';
import '../services/postgres_service.dart';
import '../services/storage_service.dart';
import '../widgets/log_output.dart';
import '../widgets/nginx_setup_dialog.dart';
import '../widgets/vscode_install_dialog.dart';
import 'home_screen.dart';
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

    setState(() {
      _projects = projects;
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

  Future<void> _openInBrowser(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
    final url = 'https://${proj.nginxSubdomain}$dotSuffix';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
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
    final installed = await PlatformService.isVscodeInstalled();
    if (!installed) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => const VscodeInstallDialog(),
      );
      return;
    }
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

  void _runGitPull(ProjectInfo project) {
    // Detect script: .sh for macOS/Linux, .ps1 for Windows
    final shPath = p.join(project.path, 'git-repositories.sh');
    final ps1Path = p.join(project.path, 'git-repositories.ps1');
    final scriptPath = Platform.isWindows
        ? (File(ps1Path).existsSync() ? ps1Path : null)
        : (File(shPath).existsSync() ? shPath : null);
    if (scriptPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.gitPullNoScript)),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => _GitPullDialog(
        projectName: project.name,
        projectPath: project.path,
        scriptPath: scriptPath,
      ),
    );
  }

  void _runGitCommit(ProjectInfo project) {
    if (!Directory(project.path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpen(project.path))),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => _GitCommitDialog(
        projectName: project.name,
        projectPath: project.path,
      ),
    );
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

      // Preserve nginxSubdomain, favourite, dbName from old project
      final updated = result.copyWith(
        nginxSubdomain: project.nginxSubdomain != null
            ? () => project.nginxSubdomain
            : null,
        favourite: project.favourite,
        dbName: project.dbName != null ? () => project.dbName : null,
      );

      await StorageService.removeProject(project.path);
      await StorageService.addProject(updated.toJson());

      // Update odoo.conf if ports changed
      final portsChanged = project.httpPort != result.httpPort ||
          project.longpollingPort != result.longpollingPort;
      if (portsChanged) {
        await _updateOdooConf(result.path, result.httpPort, result.longpollingPort);
        // Update nginx conf if project has nginx setup
        if (project.hasNginx) {
          await _updateNginxConf(
            project.nginxSubdomain!,
            result.httpPort,
            result.longpollingPort,
          );
        }
      }

      await _load();
    }
  }

  Future<void> _updateOdooConf(String projectPath, int httpPort, int lpPort) async {
    final confFile = File(p.join(projectPath, 'odoo.conf'));
    if (!await confFile.exists()) return;
    try {
      var content = await confFile.readAsString();
      content = content.replaceFirst(
        RegExp(r'http_port\s*=\s*\d+'),
        'http_port = $httpPort',
      );
      content = content.replaceFirst(
        RegExp(r'longpolling_port\s*=\s*\d+'),
        'longpolling_port = $lpPort',
      );
      await confFile.writeAsString(content);
    } catch (_) {}
  }

  Future<void> _updateNginxConf(String subdomain, int httpPort, int lpPort) async {
    try {
      await NginxService.setupOdoo(
        subdomain: subdomain,
        httpPort: httpPort,
        longpollingPort: lpPort,
      );
    } catch (_) {}
  }

  Future<void> _linkNginx(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final confDir = (nginx['confDir'] ?? '').toString();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (confDir.isEmpty || suffix.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxNotConfigured)),
        );
      }
      return;
    }

    final existingSubs = await NginxService.getExistingSubdomains(confDir);
    if (existingSubs.isEmpty) return;

    final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';

    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.l10n.nginxLink),
        children: existingSubs.map((sub) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, sub),
            child: ListTile(
              leading: const Icon(Icons.dns, color: Colors.green),
              title: Text(sub),
              subtitle: Text('$sub$dotSuffix'),
              dense: true,
            ),
          );
        }).toList(),
      ),
    );
    if (selected == null) return;

    // Read ports from nginx conf and update project + odoo.conf
    final ports = await NginxService.parseOdooPorts(confDir, selected);
    var updated = proj.copyWith(nginxSubdomain: () => selected);
    if (ports.httpPort != null && ports.lpPort != null) {
      updated = updated.copyWith(
        httpPort: ports.httpPort,
        longpollingPort: ports.lpPort,
      );
      await _updateOdooConf(proj.path, ports.httpPort!, ports.lpPort!);
    }
    await StorageService.removeProject(proj.path);
    await StorageService.addProject(updated.toJson());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nginxLinked('$selected$dotSuffix'))),
      );
    }
    await _load();
  }

  Future<void> _setupNginx(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (suffix.isEmpty || (nginx['confDir'] ?? '').toString().isEmpty) {
      // Navigate to Settings > Nginx tab (index 5)
      HomeScreen.navigateToSettings(settingsTab: 4);
      return;
    }

    final confDir = (nginx['confDir'] ?? '').toString();
    final existingSubs = await NginxService.getExistingSubdomains(confDir);
    final usedPorts = await NginxService.getUsedPorts();

    if (!mounted) return;
    final result = await showDialog<({String subdomain, int? port})>(
      context: context,
      builder: (ctx) => NginxSetupDialog(
        initialSubdomain: NginxService.sanitizeSubdomain(proj.name),
        domainSuffix: suffix,
        existingSubdomains: existingSubs,
        usedPorts: usedPorts,
      ),
    );
    if (result == null) return;

    try {
      final domain = await NginxService.setupOdoo(
        subdomain: result.subdomain,
        httpPort: proj.httpPort,
        longpollingPort: proj.longpollingPort,
      );
      // Save subdomain to project
      final updated = proj.copyWith(nginxSubdomain: () => result.subdomain);
      await StorageService.removeProject(proj.path);
      await StorageService.addProject(updated.toJson());
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
      final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
      final sub = proj.nginxSubdomain ?? subdomain;
      await NginxService.removeNginx(sub);
      // Clear subdomain from project
      final updated = proj.copyWith(nginxSubdomain: () => null);
      await StorageService.removeProject(proj.path);
      await StorageService.addProject(updated.toJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.l10n.nginxRemoveSuccess('$sub$dotSuffix'))),
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
                    if (proj.hasDb) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Chip(
                        label: Text(proj.dbName!),
                        avatar: const Icon(Icons.storage,
                            size: AppIconSize.md),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
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
                    IconButton(
                      onPressed: () => _showProjectInfo(proj),
                      icon: const Icon(Icons.info_outline),
                      tooltip: context.l10n.projectInfo,
                    ),
                    if (exists) ...[
                      IconButton(
                        onPressed: () => _runGitPull(proj),
                        icon: const Icon(Icons.sync),
                        tooltip: context.l10n.gitPull,
                      ),
                      IconButton(
                        onPressed: () => _runGitCommit(proj),
                        icon: const Icon(Icons.commit),
                        tooltip: context.l10n.gitCommit,
                      ),
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
                    if (proj.hasNginx)
                      IconButton(
                        onPressed: () => _removeNginx(proj),
                        icon: const Icon(Icons.dns, color: Colors.green),
                        tooltip: context.l10n.nginxRemove,
                      )
                    else
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.dns),
                        tooltip: context.l10n.nginxSetup,
                        onSelected: (v) {
                          if (v == 'setup') _setupNginx(proj);
                          if (v == 'link') _linkNginx(proj);
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'setup',
                            child: Row(children: [
                              const Icon(Icons.add, size: AppIconSize.md),
                              const SizedBox(width: AppSpacing.sm),
                              Text(context.l10n.nginxSetup),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'link',
                            child: Row(children: [
                              const Icon(Icons.link, size: AppIconSize.md),
                              const SizedBox(width: AppSpacing.sm),
                              Text(context.l10n.nginxLink),
                            ]),
                          ),
                        ],
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
                  child: Column(
                    children: [
                      // Nginx banner
                      if (proj.hasNginx)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          color: Colors.teal,
                          child: Text(
                            'nginx',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: portSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Expanded(
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: AppSpacing.lg,
                        children: [
                          _gridBtn(
                            icon: Icons.info_outline,
                            tooltip: context.l10n.projectInfo,
                            onPressed: () => _showProjectInfo(proj),
                            iconSize: btnSize,
                            boxSize: btnBox,
                          ),
                          if (proj.hasNginx)
                            _gridBtn(
                              icon: Icons.language,
                              tooltip: context.l10n.openInBrowser,
                              onPressed: () => _openInBrowser(proj),
                              iconSize: btnSize,
                              boxSize: btnBox,
                            ),
                          if (exists) ...[
                            _gridBtn(
                              icon: Icons.sync,
                              tooltip: context.l10n.gitPull,
                              onPressed: () => _runGitPull(proj),
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
                        ],
                      ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
          value: 'info',
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: AppIconSize.md),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.projectInfo),
            ],
          ),
        ),
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
            value: 'git_pull',
            child: Row(
              children: [
                const Icon(Icons.sync, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.gitPull),
              ],
            ),
          ),
        if (exists)
          PopupMenuItem(
            value: 'git_commit',
            child: Row(
              children: [
                const Icon(Icons.commit, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.gitCommit),
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
        if (proj.hasNginx)
          PopupMenuItem(
            value: 'nginx_remove',
            child: Row(
              children: [
                const Icon(Icons.dns, size: AppIconSize.md, color: Colors.green),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.nginxRemove),
              ],
            ),
          )
        else ...[
          PopupMenuItem(
            value: 'nginx_setup',
            child: Row(
              children: [
                const Icon(Icons.dns, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.nginxSetup),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'nginx_link',
            child: Row(
              children: [
                const Icon(Icons.link, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.nginxLink),
              ],
            ),
          ),
        ],
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
      case 'info':
        _showProjectInfo(proj);
      case 'favourite':
        _toggleFavourite(proj);
      case 'git_pull':
        _runGitPull(proj);
      case 'git_commit':
        _runGitCommit(proj);
      case 'folder':
        _openInFileManager(proj.path);
      case 'nginx_setup':
        _setupNginx(proj);
      case 'nginx_link':
        _linkNginx(proj);
      case 'nginx_remove':
        _removeNginx(proj);
      case 'edit':
        _editProject(proj);
      case 'delete':
        _remove(proj);
    }
  }

  void _showProjectInfo(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
    final domain = proj.hasNginx ? '${proj.nginxSubdomain}$dotSuffix' : null;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _ProjectInfoDialog(
        project: proj,
        domain: domain,
        onDbChanged: (dbName) async {
          final updated = proj.copyWith(dbName: () => dbName);
          await StorageService.addProject(updated.toJson());
          _load();
        },
      ),
    );
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
          Row(
            children: [
              const Icon(Icons.folder_special, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(context.l10n.projectsTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
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
              FilledButton.icon(
                onPressed: _quickCreate,
                icon: const Icon(Icons.rocket_launch),
                label: Text(context.l10n.create),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonalIcon(
                onPressed: _importProject,
                icon: const Icon(Icons.download),
                label: Text(context.l10n.import_),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.refresh,
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
  final _gitTokenController = TextEditingController();
  final _gitOrgController = TextEditingController();
  late String _projectPath;
  late String _description;
  bool _autoDetected = false;
  bool _gitTokenObscured = true;
  String? _gitScriptPath;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _httpPortController = TextEditingController(text: '${e?.httpPort ?? 0}');
    _lpPortController = TextEditingController(text: '${e?.longpollingPort ?? 0}');
    _projectPath = e?.path ?? '';
    _description = e?.description ?? '';
    if (e == null) {
      _suggestPorts();
    } else {
      _loadGitConfig(e.path);
    }
  }

  Future<void> _loadGitConfig(String projectPath) async {
    // Find script file
    final shPath = p.join(projectPath, 'git-repositories.sh');
    final ps1Path = p.join(projectPath, 'git-repositories.ps1');
    String? scriptPath;
    if (File(ps1Path).existsSync()) {
      scriptPath = ps1Path;
    } else if (File(shPath).existsSync()) {
      scriptPath = shPath;
    }
    if (scriptPath == null) return;

    _gitScriptPath = scriptPath;
    final content = await File(scriptPath).readAsString();

    // Parse TOKEN and ORG_NAME from script
    final tokenMatch = RegExp(r'(?:TOKEN|TOKEN)\s*=\s*"([^"]*)"').firstMatch(content);
    final orgMatch = RegExp(r'ORG_NAME\s*=\s*"([^"]*)"').firstMatch(content);

    if (mounted) {
      setState(() {
        _gitTokenController.text = tokenMatch?.group(1) ?? '';
        _gitOrgController.text = orgMatch?.group(1) ?? '';
      });
    }
  }

  Future<void> _suggestPorts() async {
    final projectsJson = await StorageService.loadProjects();
    int maxPort = 8068;
    for (final pr in projectsJson) {
      final hp = pr['httpPort'] as int? ?? 0;
      final lp = pr['longpollingPort'] as int? ?? 0;
      if (hp > maxPort) maxPort = hp;
      if (lp > maxPort) maxPort = lp;
    }
    final nextHttp = maxPort + 1;
    final nextLp = maxPort + 2;
    if (mounted && !_autoDetected) {
      setState(() {
        _httpPortController.text = '$nextHttp';
        _lpPortController.text = '$nextLp';
      });
    }
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

  Future<void> _save() async {
    if (_projectPath.isEmpty || _nameController.text.isEmpty) return;

    final project = ProjectInfo(
      name: _nameController.text.trim(),
      path: _projectPath,
      description: _description,
      httpPort: int.tryParse(_httpPortController.text) ?? 8069,
      longpollingPort: int.tryParse(_lpPortController.text) ?? 8072,
      createdAt: widget.existing?.createdAt ?? DateTime.now().toIso8601String(),
    );

    // Update git-repositories script if editing and script exists
    if (_gitScriptPath != null) {
      final file = File(_gitScriptPath!);
      if (await file.exists()) {
        var content = await file.readAsString();
        final newToken = _gitTokenController.text.trim();
        final newOrg = _gitOrgController.text.trim();
        if (newToken.isNotEmpty) {
          content = content.replaceFirst(
              RegExp(r'(TOKEN\s*=\s*)"[^"]*"'), '\$1"$newToken"');
        }
        if (newOrg.isNotEmpty) {
          content = content.replaceFirst(
              RegExp(r'(ORG_NAME\s*=\s*)"[^"]*"'), '\$1"$newOrg"');
        }
        await file.writeAsString(content);
      }
    }

    if (mounted) Navigator.pop(context, project);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _httpPortController.dispose();
    _lpPortController.dispose();
    _gitTokenController.dispose();
    _gitOrgController.dispose();
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

              // Git config (only when editing and script exists)
              if (widget.existing != null && _gitScriptPath != null) ...[
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Text('Git Repositories',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gitTokenController,
                  obscureText: _gitTokenObscured,
                  decoration: InputDecoration(
                    labelText: context.l10n.gitToken,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(_gitTokenObscured
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _gitTokenObscured = !_gitTokenObscured),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _gitOrgController,
                  decoration: InputDecoration(
                    labelText: context.l10n.gitOrg,
                    hintText: context.l10n.gitOrgHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
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

// ── Project Info Dialog ──

class _ProjectInfoDialog extends StatefulWidget {
  final ProjectInfo project;
  final String? domain;
  final void Function(String dbName) onDbChanged;

  const _ProjectInfoDialog({
    required this.project,
    this.domain,
    required this.onDbChanged,
  });

  @override
  State<_ProjectInfoDialog> createState() => _ProjectInfoDialogState();
}

class _ProjectInfoDialogState extends State<_ProjectInfoDialog> {
  final _dbNameController = TextEditingController();
  List<String>? _databases;
  String? _pythonPath;
  String? _odooBinPath;
  String? _confPath;
  String _dbUser = 'odoo';

  @override
  void initState() {
    super.initState();
    _dbNameController.text = widget.project.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    _detectPaths();
    _loadDatabases();
  }

  @override
  void dispose() {
    _dbNameController.dispose();
    super.dispose();
  }

  Future<void> _detectPaths() async {
    final projPath = widget.project.path;

    // Try to find odoo.conf and parse DB settings
    for (final candidate in [
      p.join(projPath, 'odoo.conf'),
      p.join(projPath, 'config', 'odoo.conf'),
    ]) {
      if (await File(candidate).exists()) {
        _confPath = candidate;
        // Parse db_user, db_host, db_port from conf
        try {
          final content = await File(candidate).readAsString();
          final userMatch = RegExp(r'^db_user\s*=\s*(.+)$', multiLine: true).firstMatch(content);
          if (userMatch != null) _dbUser = userMatch.group(1)!.trim();
        } catch (_) {}
        break;
      }
    }

    // Try to find python + odoo-bin from .vscode/launch.json
    final launchFile = File(p.join(projPath, '.vscode', 'launch.json'));
    if (await launchFile.exists()) {
      try {
        final content = await launchFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final configs = json['configurations'] as List?;
        if (configs != null && configs.isNotEmpty) {
          final config = configs.first as Map<String, dynamic>;
          _pythonPath = config['python']?.toString();
          _odooBinPath = config['program']?.toString();
          // Resolve ${workspaceFolder}
          if (_odooBinPath != null) {
            _odooBinPath =
                _odooBinPath!.replaceAll(r'${workspaceFolder}', projPath);
          }
        }
      } catch (_) {}
    }

    // Fallback: look for common paths
    _odooBinPath ??= await _findFile([
      p.join(projPath, 'odoo', 'odoo-bin'),
      p.join(projPath, 'odoo-bin'),
    ]);
    _pythonPath ??= await _findFile([
      PlatformService.venvPython(p.join(projPath, 'venv')),
      PlatformService.venvPython(p.join(projPath, '.venv')),
    ]);

    if (mounted) setState(() {});
  }

  Future<void> _loadDatabases() async {
    try {
      final servers = await PostgresService.detectServers();
      final dockerServer = servers
          .where((s) =>
              s.source == PgServerSource.docker &&
              s.containerRunning == true &&
              s.containerName != null)
          .toList();
      if (dockerServer.isEmpty) return;

      final container = dockerServer.first.containerName!;
      final docker = await PlatformService.dockerPath;
      final result = await Process.run(
        docker,
        ['exec', container, 'psql', '-U', _dbUser, '-d', 'postgres', '-t', '-A', '-c',
         "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres') ORDER BY datname;"],
        runInShell: true,
      );
      if (result.exitCode == 0 && mounted) {
        setState(() {
          _databases = result.stdout
              .toString()
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<String?> _findFile(List<String> candidates) async {
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }


  void _showCreateDbDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _CreateDbDialog(
        defaultName: _dbNameController.text,
        pythonPath: _pythonPath,
        odooBinPath: _odooBinPath,
        confPath: _confPath,
        dbUser: _dbUser,
        projectPath: widget.project.path,
        onCreated: (dbName) {
          setState(() => _dbNameController.text = dbName);
          widget.onDbChanged(dbName);
        },
      ),
    );
  }

  Future<void> _selectDatabase() async {
    // Load databases if not yet loaded
    if (_databases == null || _databases!.isEmpty) {
      await _loadDatabases();
    }
    if (_databases == null || _databases!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noPostgresContainer)),
        );
      }
      return;
    }
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Database'),
        children: _databases!.map((db) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, db),
          child: Row(
            children: [
              const Icon(Icons.storage, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Text(db, style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
        )).toList(),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _dbNameController.text = selected);
    await _updateDbFilter(selected);
    widget.onDbChanged(selected);
  }

  Future<void> _updateDbFilter(String dbName) async {
    if (_confPath == null) return;
    try {
      final file = File(_confPath!);
      var content = await file.readAsString();
      final regex = RegExp(r'^dbfilter\s*=.*$', multiLine: true);
      if (regex.hasMatch(content)) {
        content = content.replaceFirst(regex, 'dbfilter = ^$dbName.*\$');
      }
      final dbNameRegex = RegExp(r'^db_name\s*=.*$', multiLine: true);
      if (dbNameRegex.hasMatch(content)) {
        content = content.replaceFirst(dbNameRegex, 'db_name = $dbName');
      }
      await file.writeAsString(content);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final proj = widget.project;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(proj.name)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info section
              _infoRow(Icons.folder, context.l10n.projectDirectory, proj.path),
              const SizedBox(height: AppSpacing.md),
              _infoRow(Icons.lan, 'HTTP Port', '${proj.httpPort}'),
              const SizedBox(height: AppSpacing.sm),
              _infoRow(Icons.lan, 'Longpolling Port', '${proj.longpollingPort}'),
              const SizedBox(height: AppSpacing.md),
              _infoRow(
                Icons.dns,
                context.l10n.projectInfoDomain,
                widget.domain != null
                    ? 'https://${widget.domain}'
                    : context.l10n.projectInfoNginxNotSetup,
                valueColor: widget.domain != null ? Colors.green : Colors.orange,
              ),
              _infoRow(
                Icons.storage,
                'Database',
                proj.hasDb ? proj.dbName! : '—',
                valueColor: proj.hasDb ? null : Colors.grey,
              ),
              if (proj.description.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _infoRow(Icons.description, context.l10n.descriptionOptional,
                    proj.description),
              ],

              // Database actions
              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showCreateDbDialog(),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.createDatabase),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _selectDatabase,
                      icon: const Icon(Icons.list),
                      label: Text(context.l10n.import_),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: Colors.grey),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 170,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: AppFontSize.xl)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppFontSize.xl,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create Database Dialog ──

class _CreateDbDialog extends StatefulWidget {
  final String defaultName;
  final String? pythonPath;
  final String? odooBinPath;
  final String? confPath;
  final String dbUser;
  final String projectPath;
  final void Function(String dbName) onCreated;

  const _CreateDbDialog({
    required this.defaultName,
    this.pythonPath,
    this.odooBinPath,
    this.confPath,
    required this.dbUser,
    required this.projectPath,
    required this.onCreated,
  });

  @override
  State<_CreateDbDialog> createState() => _CreateDbDialogState();
}

class _CreateDbDialogState extends State<_CreateDbDialog> {
  late final TextEditingController _nameController;
  String _language = 'en_US';
  bool _demoData = false;
  bool _creating = false;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final dbName = _nameController.text.trim();
    if (dbName.isEmpty) return;

    setState(() {
      _creating = true;
      _logLines.clear();
    });

    void log(String line) {
      if (mounted) setState(() => _logLines.add(line));
    }

    try {
      // Step 1: Create PostgreSQL database via Docker
      log('[+] Creating PostgreSQL database "$dbName"...');
      final servers = await PostgresService.detectServers();
      final dockerServer = servers
          .where((s) =>
              s.source == PgServerSource.docker &&
              s.containerRunning == true &&
              s.containerName != null)
          .toList();

      if (dockerServer.isEmpty) {
        if (!mounted) return;
        log('[ERROR] ${context.l10n.noPostgresContainer}');
        setState(() => _creating = false);
        return;
      }

      final container = dockerServer.first.containerName!;
      final docker = await PlatformService.dockerPath;

      final createResult = await Process.run(
        docker,
        ['exec', container, 'createdb', '-U', widget.dbUser, '--maintenance-db=postgres', dbName],
        runInShell: true,
      );

      if (createResult.exitCode != 0) {
        final err = createResult.stderr.toString().trim();
        if (!err.contains('already exists')) {
          log('[ERROR] $err');
          setState(() => _creating = false);
          return;
        }
        log('[WARN] Database "$dbName" already exists, initializing...');
      } else {
        log('[+] Database "$dbName" created');
      }

      // Step 2: Initialize Odoo
      if (widget.pythonPath == null || widget.odooBinPath == null || widget.confPath == null) {
        log('[+] Database created. Start Odoo to initialize modules.');
        if (widget.pythonPath == null) log('[WARN] Python not found');
        if (widget.odooBinPath == null) log('[WARN] odoo-bin not found');
        if (widget.confPath == null) log('[WARN] odoo.conf not found');
        widget.onCreated(dbName);
        setState(() => _creating = false);
        return;
      }

      log('');
      log('[+] Initializing Odoo database (this may take a few minutes)...');

      final args = [
        widget.odooBinPath!,
        '-c', widget.confPath!,
        '-d', dbName,
        '-i', 'base',
        '--stop-after-init',
        '--load-language=$_language',
        if (!_demoData) '--without-demo=all',
      ];

      final process = await Process.start(
        widget.pythonPath!,
        args,
        runInShell: true,
        workingDirectory: widget.projectPath,
      );

      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) log(line.trim());
        }
      });
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) log(line.trim());
        }
      });

      final exitCode = await process.exitCode;

      if (mounted) {
        if (exitCode == 0) {
          // Update odoo.conf
          if (widget.confPath != null) {
            try {
              final file = File(widget.confPath!);
              var content = await file.readAsString();
              final dbFilterRegex = RegExp(r'^dbfilter\s*=.*$', multiLine: true);
              if (dbFilterRegex.hasMatch(content)) {
                content = content.replaceFirst(dbFilterRegex, 'dbfilter = ^$dbName.*\$');
              }
              final dbNameRegex = RegExp(r'^db_name\s*=.*$', multiLine: true);
              if (dbNameRegex.hasMatch(content)) {
                content = content.replaceFirst(dbNameRegex, 'db_name = $dbName');
              }
              await file.writeAsString(content);
              log('[+] Updated odoo.conf');
            } catch (_) {}
          }
          log('');
          if (mounted) log('[+] ${context.l10n.dbCreated(dbName)}');
          widget.onCreated(dbName);
        } else {
          log('');
          log('[ERROR] Odoo init failed with exit code $exitCode');
        }
        setState(() => _creating = false);
      }
    } catch (e) {
      log('[ERROR] $e');
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.createDatabase),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.projectInfoDbName,
                  hintText: context.l10n.projectInfoDbNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                enabled: !_creating,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _language,
                      decoration: InputDecoration(
                        labelText: context.l10n.language,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'en_US', child: Text('English')),
                        DropdownMenuItem(value: 'vi_VN', child: Text('Tiếng Việt')),
                        DropdownMenuItem(value: 'ko_KR', child: Text('한국어')),
                        DropdownMenuItem(value: 'fr_FR', child: Text('Français')),
                        DropdownMenuItem(value: 'de_DE', child: Text('Deutsch')),
                        DropdownMenuItem(value: 'ja_JP', child: Text('日本語')),
                        DropdownMenuItem(value: 'zh_CN', child: Text('中文(简体)')),
                      ],
                      onChanged: _creating ? null : (v) => setState(() => _language = v!),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  FilterChip(
                    label: const Text('Demo data'),
                    selected: _demoData,
                    onSelected: _creating ? null : (v) => setState(() => _demoData = v),
                  ),
                ],
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 250),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        FilledButton.icon(
          onPressed: _creating || _nameController.text.trim().isEmpty ? null : _create,
          icon: _creating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(_creating ? context.l10n.creatingDatabase : context.l10n.createDatabase),
        ),
      ],
    );
  }
}

class _GitPullDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;
  final String scriptPath;

  const _GitPullDialog({
    required this.projectName,
    required this.projectPath,
    required this.scriptPath,
  });

  @override
  State<_GitPullDialog> createState() => _GitPullDialogState();
}

class _GitPullDialogState extends State<_GitPullDialog> {
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    30: Color(0xFF000000), // black
    31: Color(0xFFCD3131), // red
    32: Color(0xFF0DBC79), // green
    33: Color(0xFFE5E510), // yellow
    34: Color(0xFF2472C8), // blue
    35: Color(0xFFBC3FBC), // magenta
    36: Color(0xFF11A8CD), // cyan
    37: Color(0xFFE5E5E5), // white
    90: Color(0xFF666666), // bright black (gray)
    91: Color(0xFFF14C4C), // bright red
    92: Color(0xFF23D18B), // bright green
    93: Color(0xFFF5F543), // bright yellow
    94: Color(0xFF3B8EEA), // bright blue
    95: Color(0xFFD670D6), // bright magenta
    96: Color(0xFF29B8DB), // bright cyan
    97: Color(0xFFFFFFFF), // bright white
  };

  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _addLine(String line) {
    if (line.contains('\r')) line = line.split('\r').last;
    if (line.trim().isEmpty) return;
    setState(() => _logLines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final String executable;
      final List<String> args;
      if (Platform.isWindows) {
        executable = 'powershell';
        args = ['-ExecutionPolicy', 'Bypass', '-File', widget.scriptPath];
      } else {
        executable = 'bash';
        args = [widget.scriptPath];
      }
      final process = await Process.start(
        executable,
        args,
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (mounted) _addLine(line);
      });
      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (mounted) _addLine(line);
      });
      final exitCode = await process.exitCode;
      if (!mounted) return;
      if (exitCode == 0) {
        _addLine('\x1B[0;32m[+] ${context.l10n.gitPullDone}\x1B[0m');
      } else {
        _addLine('\x1B[0;31m[-] ${context.l10n.gitPullFailed(exitCode)}\x1B[0m');
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) setState(() => _running = false);
  }

  List<TextSpan> _parseAnsi(String line) {
    final spans = <TextSpan>[];
    final defaultColor = Colors.grey.shade300;
    var currentColor = defaultColor;
    var lastEnd = 0;

    for (final match in _ansiRegex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: line.substring(lastEnd, match.start),
          style: TextStyle(color: currentColor),
        ));
      }
      final code = match.group(0)!;
      final params = code.substring(2, code.length - 1).split(';');
      for (final p in params) {
        final n = int.tryParse(p) ?? 0;
        if (n == 0) {
          currentColor = defaultColor;
        } else if (_ansiColors.containsKey(n)) {
          currentColor = _ansiColors[n]!;
        }
      }
      lastEnd = match.end;
    }
    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: TextStyle(color: currentColor),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.gitPullTitle(widget.projectName)),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_running)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            Container(
              height: 350,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppLogColors.terminalBg,
                borderRadius: AppRadius.mediumBorderRadius,
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: _logLines.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.noOutputYet,
                        style: const TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                      ),
                    )
                  : SelectionArea(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in _logLines)
                                Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: AppFontSize.md,
                                    ),
                                    children: _parseAnsi(line),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

// ── Git Commit Dialog ──

class _RepoStatus {
  final String name;
  final String path;
  final int changedFiles;
  bool selected;

  _RepoStatus({
    required this.name,
    required this.path,
    required this.changedFiles,
  }) : selected = true;
}

class _GitCommitDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const _GitCommitDialog({
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<_GitCommitDialog> createState() => _GitCommitDialogState();
}

class _GitCommitDialogState extends State<_GitCommitDialog> {
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    30: Color(0xFF000000),
    31: Color(0xFFCD3131),
    32: Color(0xFF0DBC79),
    33: Color(0xFFE5E510),
    34: Color(0xFF2472C8),
    35: Color(0xFFBC3FBC),
    36: Color(0xFF11A8CD),
    37: Color(0xFFE5E5E5),
    90: Color(0xFF666666),
    91: Color(0xFFF14C4C),
    92: Color(0xFF23D18B),
    93: Color(0xFFF5F543),
    94: Color(0xFF3B8EEA),
    95: Color(0xFFD670D6),
    96: Color(0xFF29B8DB),
    97: Color(0xFFFFFFFF),
  };

  final List<_RepoStatus> _repos = [];
  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  bool _scanning = true;
  bool _running = false;
  bool _pushAfterCommit = false;

  @override
  void initState() {
    super.initState();
    _scanRepos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _addLine(String line) {
    if (line.contains('\r')) line = line.split('\r').last;
    if (line.trim().isEmpty) return;
    setState(() => _logLines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _scanRepos() async {
    setState(() => _scanning = true);
    try {
      final addonsDir = Directory(p.join(widget.projectPath, 'addons'));
      if (!await addonsDir.exists()) {
        setState(() => _scanning = false);
        return;
      }
      final entries = await addonsDir.list().toList();
      for (final entry in entries) {
        if (entry is! Directory) continue;
        final gitDir = Directory(p.join(entry.path, '.git'));
        if (!await gitDir.exists()) continue;
        final result = await Process.run(
          'git',
          ['status', '--porcelain'],
          workingDirectory: entry.path,
          runInShell: true,
        );
        final output = (result.stdout as String).trim();
        if (output.isEmpty) continue;
        final fileCount = LineSplitter.split(output).length;
        _repos.add(_RepoStatus(
          name: p.basename(entry.path),
          path: entry.path,
          changedFiles: fileCount,
        ));
      }
      _repos.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) setState(() => _scanning = false);
  }

  int get _selectedCount => _repos.where((r) => r.selected).length;

  bool get _canCommit =>
      !_running &&
      !_scanning &&
      _selectedCount > 0 &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    final selected = _repos.where((r) => r.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _running = true);
    for (final repo in selected) {
      _addLine('\x1B[0;34m[*] ${repo.name}\x1B[0m');

      // git add -A
      final addResult = await Process.run(
        'git',
        ['add', '-A'],
        workingDirectory: repo.path,
        runInShell: true,
      );
      if (addResult.exitCode != 0) {
        _addLine('\x1B[0;31m[-] git add failed: ${addResult.stderr}\x1B[0m');
        continue;
      }

      // git commit
      final commitResult = await Process.run(
        'git',
        ['commit', '-m', message],
        workingDirectory: repo.path,
        runInShell: true,
      );
      final commitOut = (commitResult.stdout as String).trim();
      if (commitOut.isNotEmpty) _addLine(commitOut);
      if (commitResult.exitCode != 0) {
        final errOut = (commitResult.stderr as String).trim();
        if (errOut.isNotEmpty) _addLine('\x1B[0;31m$errOut\x1B[0m');
        if (mounted) {
          _addLine(
              '\x1B[0;31m[-] ${context.l10n.gitCommitFailed(commitResult.exitCode)}\x1B[0m');
        }
        continue;
      }

      // git push (optional)
      if (_pushAfterCommit) {
        _addLine('\x1B[0;36m[>] Pushing ${repo.name}...\x1B[0m');
        final pushProcess = await Process.start(
          'git',
          ['push'],
          workingDirectory: repo.path,
          runInShell: true,
        );
        pushProcess.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (mounted) _addLine(line);
        });
        pushProcess.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (mounted) _addLine(line);
        });
        final pushExit = await pushProcess.exitCode;
        if (pushExit != 0 && mounted) {
          _addLine('\x1B[0;31m[-] Push failed for ${repo.name}\x1B[0m');
        }
      }

      if (mounted) {
        _addLine('\x1B[0;32m[+] ${repo.name}: ${context.l10n.gitCommitDone}\x1B[0m');
      }
    }
    if (mounted) setState(() => _running = false);
  }

  void _toggleAll(bool select) {
    setState(() {
      for (final r in _repos) {
        r.selected = select;
      }
    });
  }

  List<TextSpan> _parseAnsi(String line) {
    final spans = <TextSpan>[];
    final defaultColor = Colors.grey.shade300;
    var currentColor = defaultColor;
    var lastEnd = 0;

    for (final match in _ansiRegex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: line.substring(lastEnd, match.start),
          style: TextStyle(color: currentColor),
        ));
      }
      final code = match.group(0)!;
      final params = code.substring(2, code.length - 1).split(';');
      for (final param in params) {
        final n = int.tryParse(param) ?? 0;
        if (n == 0) {
          currentColor = defaultColor;
        } else if (_ansiColors.containsKey(n)) {
          currentColor = _ansiColors[n]!;
        }
      }
      lastEnd = match.end;
    }
    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: TextStyle(color: currentColor),
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.gitCommitTitle(widget.projectName)),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scanning)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            if (!_scanning && _repos.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  context.l10n.gitNoReposWithChanges,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            if (_repos.isNotEmpty) ...[
              // Select all / Deselect all
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _running
                        ? null
                        : () => _toggleAll(_selectedCount < _repos.length),
                    icon: Icon(
                      _selectedCount == _repos.length
                          ? Icons.deselect
                          : Icons.select_all,
                      size: AppIconSize.md,
                    ),
                    label: Text(
                      _selectedCount == _repos.length
                          ? context.l10n.gitDeselectAll
                          : context.l10n.gitSelectAll,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.gitStagedFiles(_selectedCount),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Repo list
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _repos.length,
                  itemBuilder: (ctx, i) {
                    final repo = _repos[i];
                    return CheckboxListTile(
                      dense: true,
                      value: repo.selected,
                      onChanged: _running
                          ? null
                          : (v) => setState(() => repo.selected = v ?? false),
                      title: Text(repo.name),
                      subtitle: Text(
                        '${repo.changedFiles} file(s)',
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Commit message
              TextField(
                controller: _messageController,
                enabled: !_running,
                decoration: InputDecoration(
                  labelText: context.l10n.gitCommitMessage,
                  hintText: context.l10n.gitCommitMessageHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Push after commit checkbox
              Row(
                children: [
                  Checkbox(
                    value: _pushAfterCommit,
                    onChanged: _running
                        ? null
                        : (v) => setState(() => _pushAfterCommit = v ?? false),
                  ),
                  GestureDetector(
                    onTap: _running
                        ? null
                        : () => setState(
                            () => _pushAfterCommit = !_pushAfterCommit),
                    child: Text(context.l10n.gitPushAfterCommit),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_running)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              ),
            // Log output
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppLogColors.terminalBg,
                borderRadius: AppRadius.mediumBorderRadius,
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: _logLines.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.noOutputYet,
                        style: const TextStyle(
                            color: Colors.grey, fontFamily: 'monospace'),
                      ),
                    )
                  : SelectionArea(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in _logLines)
                                Text.rich(
                                  TextSpan(
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: AppFontSize.md,
                                    ),
                                    children: _parseAnsi(line),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (_repos.isNotEmpty && !_running && _logLines.isEmpty)
          FilledButton(
            onPressed: _canCommit ? _commit : null,
            child: Text(
              _pushAfterCommit
                  ? context.l10n.gitCommitAndPush
                  : context.l10n.gitCommitOnly,
            ),
          ),
        TextButton(
          onPressed: (_running || _scanning) ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
