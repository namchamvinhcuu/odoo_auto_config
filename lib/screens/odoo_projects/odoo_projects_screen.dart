import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../constants/app_constants.dart';
import '../../models/project_info.dart';
import '../../l10n/l10n_extension.dart';
import '../../services/platform_service.dart';
import '../../services/nginx_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/nginx_setup_dialog.dart';
import '../../widgets/vscode_install_dialog.dart';
import '../home_screen.dart';
import '../odoo_workspace/odoo_workspace_dialog.dart';
import '../quick_create_screen.dart';
import 'git_commit_dialog.dart';
import 'git_pull_dialog.dart';
import 'import_project_dialog.dart';
import 'project_info_dialog.dart';
import 'selective_pull_dialog.dart';

class OdooProjectsScreen extends StatefulWidget {
  const OdooProjectsScreen({super.key});

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
  State<OdooProjectsScreen> createState() => _OdooProjectsScreenState();
}

class _OdooProjectsScreenState extends State<OdooProjectsScreen> {
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
    final created = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => const QuickCreateDialog(),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _importProject() async {
    final result = await AppDialog.show<ProjectInfo>(
      context: context,
      builder: (ctx) => const ImportProjectDialog(),
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
      AppDialog.show(
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
    AppDialog.show(
      context: context,
      builder: (ctx) => GitPullDialog(
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
    AppDialog.show(
      context: context,
      builder: (ctx) => GitCommitDialog(
        projectName: project.name,
        projectPath: project.path,
      ),
    );
  }

  void _openWorkspaceView(ProjectInfo project) {
    if (!Directory(project.path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpen(project.path))),
      );
      return;
    }
    AppDialog.show(
      context: context,
      builder: (ctx) => OdooWorkspaceDialog(
        projectName: project.name,
        projectPath: project.path,
      ),
    );
  }

  void _runSelectivePull(ProjectInfo project) {
    final addonsDir = Directory(p.join(project.path, 'addons'));
    if (!addonsDir.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.gitNoReposFound)),
      );
      return;
    }
    AppDialog.show(
      context: context,
      builder: (ctx) => SelectivePullDialog(
        projectName: project.name,
        projectPath: project.path,
      ),
    );
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
    final selected = await AppDialog.show<String>(
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
    final result = await AppDialog.show<({String subdomain, int? port})>(
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
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(context.l10n.nginxRemove),
            const Spacer(),
            AppDialog.closeButton(ctx, onClose: () => Navigator.pop(ctx, false)),
          ],
        ),
        content: Text(context.l10n.nginxConfirmRemove(proj.name)),
        actions: [
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

    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Text(context.l10n.deleteProjectTitle),
              const Spacer(),
              AppDialog.closeButton(ctx, onClose: () => Navigator.pop(ctx, false)),
            ],
          ),
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
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: Text(context.l10n.delete)),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      // Cleanup nginx config if project has one
      if (project.hasNginx) {
        try {
          final sub = project.nginxSubdomain!;
          await NginxService.removeNginx(sub);
        } catch (_) {}
      }
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
                        onPressed: () => _openWorkspaceView(proj),
                        icon: const Icon(Icons.workspaces),
                        tooltip: context.l10n.workspaceView,
                      ),
                      IconButton(
                        onPressed: () => _runGitPull(proj),
                        icon: const Icon(Icons.sync),
                        tooltip: context.l10n.gitPull,
                      ),
                      // Selective Pull — hidden, use Workspace View instead
                      // IconButton(
                      //   onPressed: () => _runSelectivePull(proj),
                      //   icon: const Icon(Icons.checklist),
                      //   tooltip: context.l10n.gitSelectivePull,
                      // ),
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
                    ],
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
    if (width >= 1100) return 4;
    if (width >= 800) return 3;
    return 2;
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.xs,
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
                              icon: Icons.workspaces,
                              tooltip: context.l10n.workspaceView,
                              onPressed: () => _openWorkspaceView(proj),
                              iconSize: btnSize,
                              boxSize: btnBox,
                            ),
                            // Selective Pull — hidden, use Workspace View instead
                            // _gridBtn(
                            //   icon: Icons.checklist,
                            //   tooltip: context.l10n.gitSelectivePull,
                            //   onPressed: () => _runSelectivePull(proj),
                            //   iconSize: btnSize,
                            //   boxSize: btnBox,
                            // ),
                            _gridBtn(
                              icon: Icons.commit,
                              tooltip: context.l10n.gitCommit,
                              onPressed: () => _runGitCommit(proj),
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
            value: 'workspace_view',
            child: Row(
              children: [
                const Icon(Icons.workspaces, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.workspaceView),
              ],
            ),
          ),
        // Selective Pull — hidden, use Workspace View instead
        // if (exists)
        //   PopupMenuItem(
        //     value: 'git_selective_pull',
        //     child: Row(
        //       children: [
        //         const Icon(Icons.checklist, size: AppIconSize.md),
        //         const SizedBox(width: AppSpacing.sm),
        //         Text(context.l10n.gitSelectivePull),
        //       ],
        //     ),
        //   ),
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
      case 'workspace_view':
        _openWorkspaceView(proj);
      case 'git_pull':
        _runGitPull(proj);
      case 'git_selective_pull':
        _runSelectivePull(proj);
      case 'git_commit':
        _runGitCommit(proj);
      case 'folder':
        _openInFileManager(proj.path);
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
    AppDialog.show(
      context: context,
      builder: (ctx) => ProjectInfoDialog(
        project: proj,
        domain: domain,
        domainSuffix: dotSuffix,
        onDbChanged: (dbName) async {
          final updated = proj.copyWith(dbName: () => dbName);
          await StorageService.addProject(updated.toJson());
          _load();
        },
        onSaved: (updated) async {
          final full = updated.copyWith(
            nginxSubdomain: proj.nginxSubdomain != null
                ? () => proj.nginxSubdomain
                : null,
            favourite: proj.favourite,
            dbName: proj.dbName != null ? () => proj.dbName : null,
          );

          await StorageService.removeProject(proj.path);
          await StorageService.addProject(full.toJson());

          if (proj.httpPort != updated.httpPort ||
              proj.longpollingPort != updated.longpollingPort) {
            await _updateOdooConf(updated.path, updated.httpPort, updated.longpollingPort);
            if (proj.hasNginx) {
              await _updateNginxConf(proj.nginxSubdomain!, updated.httpPort, updated.longpollingPort);
            }
          }

          await _load();
        },
        onNginxSetup: (p) async {
          Navigator.pop(ctx);
          await _setupNginx(p);
        },
        onNginxLink: (p) async {
          Navigator.pop(ctx);
          await _linkNginx(p);
        },
        onNginxRemove: (p) async {
          Navigator.pop(ctx);
          await _removeNginx(p);
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
                  setState(() => OdooProjectsScreen.gridView = !OdooProjectsScreen.gridView);
                  OdooProjectsScreen.saveViewPreference();
                },
                icon: Icon(OdooProjectsScreen.gridView ? Icons.view_list : Icons.grid_view),
                tooltip: OdooProjectsScreen.gridView
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
              child: OdooProjectsScreen.gridView ? _buildGridView() : _buildListView(),
            ),
        ],
      ),
    );
  }
}
