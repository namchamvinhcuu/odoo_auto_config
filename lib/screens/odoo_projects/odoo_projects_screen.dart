import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/odoo_projects_provider.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/nginx_setup_dialog.dart';
import 'package:odoo_auto_config/widgets/vscode_install_dialog.dart';
import 'package:odoo_auto_config/screens/home_screen.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/odoo_workspace_dialog.dart';
import 'package:odoo_auto_config/screens/quick_create_screen.dart';
import 'git_commit_dialog.dart';
import 'git_pull_dialog.dart';
import 'import_project_dialog.dart';
import 'project_info_dialog.dart';
import 'odoo_project_grid_view.dart';
import 'odoo_project_list_view.dart';
import 'selective_pull_dialog.dart';

class OdooProjectsScreen extends ConsumerStatefulWidget {
  const OdooProjectsScreen({super.key});

  @override
  ConsumerState<OdooProjectsScreen> createState() => _OdooProjectsScreenState();
}

class _OdooProjectsScreenState extends ConsumerState<OdooProjectsScreen> {
  final _searchController = TextEditingController();
  String? _selectedPath;

  List<ProjectInfo> _applyFilter(List<ProjectInfo> projects) {
    final q = _searchController.text.toLowerCase();
    if (q.isEmpty) return projects;
    return projects.where((p) {
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
      ref.read(odooProjectsProvider.notifier).reload();
    }
  }

  Future<void> _importProject() async {
    final result = await AppDialog.show<ProjectInfo>(
      context: context,
      builder: (ctx) => const ImportProjectDialog(),
    );
    if (result != null) {
      final conflict = await ref
          .read(odooProjectsProvider.notifier)
          .checkPortConflict(result);
      if (conflict != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(conflict), backgroundColor: Colors.red),
        );
        return;
      }
      await ref.read(odooProjectsProvider.notifier).addProject(result);
    }
  }

  Future<void> _openInBrowser(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
    final url = 'https://${proj.nginxSubdomain}$dotSuffix';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url], runInShell: true);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url], runInShell: true);
      } else {
        await Process.run('xdg-open', [url], runInShell: true);
      }
    } catch (_) {}
  }

  Future<void> _openInFileManager(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path], runInShell: true);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path], runInShell: true);
      } else {
        await Process.run('xdg-open', [path], runInShell: true);
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
        await Process.run('open', ['-a', 'Visual Studio Code', path], runInShell: true);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'code', path], runInShell: true);
      } else {
        await Process.run('code', [path], runInShell: true);
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
        nginxSubdomain: project.nginxSubdomain,
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

  Future<void> _setupNginx(ProjectInfo proj) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (suffix.isEmpty || (nginx['confDir'] ?? '').toString().isEmpty) {
      HomeScreen.navigateToSettings(settingsTab: 4);
      return;
    }

    final confDir = (nginx['confDir'] ?? '').toString();
    final existingSubs = await NginxService.getExistingSubdomains(confDir);
    final usedPorts = await NginxService.getUsedPorts();

    if (!mounted) return;
    final result = await AppDialog.show<NginxSetupResult>(
      context: context,
      builder: (ctx) => NginxSetupDialog(
        initialSubdomain: NginxService.sanitizeSubdomain(proj.name),
        domainSuffix: suffix,
        existingSubdomains: existingSubs,
        usedPorts: usedPorts,
      ),
    );
    if (result == null) return;

    if (result.isLink) {
      try {
        final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
        // Read ports from nginx conf and update project + odoo.conf
        final ports = await NginxService.parseOdooPorts(confDir, result.subdomain);
        var updated = proj.copyWith(nginxSubdomain: () => result.subdomain);
        if (ports.httpPort != null && ports.lpPort != null) {
          updated = updated.copyWith(
            httpPort: ports.httpPort,
            longpollingPort: ports.lpPort,
          );
          await _updateOdooConf(proj.path, ports.httpPort!, ports.lpPort!);
        }
        await ref.read(odooProjectsProvider.notifier).updateProject(proj, updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.nginxLinked('${result.subdomain}$dotSuffix'))),
          );
        }
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
      return;
    }

    try {
      final domain = await NginxService.setupOdoo(
        subdomain: result.subdomain,
        httpPort: proj.httpPort,
        longpollingPort: proj.longpollingPort,
      );
      final updated = proj.copyWith(nginxSubdomain: () => result.subdomain);
      await ref.read(odooProjectsProvider.notifier).updateProject(proj, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxSetupSuccess(domain))),
        );
      }
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
      await ref.read(odooProjectsProvider.notifier).updateProject(proj, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.l10n.nginxRemoveSuccess('$sub$dotSuffix'))),
        );
      }
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
    await ref.read(odooProjectsProvider.notifier).toggleFavourite(proj);
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
      await ref.read(odooProjectsProvider.notifier).deleteProject(project);
    }
  }

  // ── List View ──

  Widget _buildListView(List<ProjectInfo> filtered) {
    return OdooProjectListView(
      projects: filtered,
      onToggleFavourite: _toggleFavourite,
      onShowInfo: _showProjectInfo,
      onOpenWorkspace: _openWorkspaceView,
      onGitPull: _runGitPull,
      onGitCommit: _runGitCommit,
      onOpenInVscode: (proj) => _openInVscode(proj.path),
      onRemove: _remove,
    );
  }

  // ── Grid View ──

  Widget _buildGridView(List<ProjectInfo> filtered) {
    return OdooProjectGridView(
      projects: filtered,
      selectedPath: _selectedPath,
      onToggleFavourite: _toggleFavourite,
      onShowInfo: _showProjectInfo,
      onOpenWorkspace: _openWorkspaceView,
      onGitPull: _runGitPull,
      onGitCommit: _runGitCommit,
      onSelectivePull: _runSelectivePull,
      onSelect: (proj) => setState(() => _selectedPath = _selectedPath == proj.path ? null : proj.path),
      onOpenInVscode: (proj) => _openInVscode(proj.path),
      onOpenInFileManager: (proj) => _openInFileManager(proj.path),
      onOpenInBrowser: _openInBrowser,
      onRemove: _remove,
    );
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
          await ref.read(odooProjectsProvider.notifier).updateProject(proj, updated);
        },
        onSaved: (updated) async {
          final full = updated.copyWith(
            nginxSubdomain: proj.nginxSubdomain != null
                ? () => proj.nginxSubdomain
                : null,
            favourite: proj.favourite,
            dbName: proj.dbName != null ? () => proj.dbName : null,
          );

          await ref.read(odooProjectsProvider.notifier).updateProject(proj, full);

          if (proj.httpPort != updated.httpPort ||
              proj.longpollingPort != updated.longpollingPort) {
            await _updateOdooConf(updated.path, updated.httpPort, updated.longpollingPort);
            if (proj.hasNginx) {
              await _updateNginxConf(proj.nginxSubdomain!, updated.httpPort, updated.longpollingPort);
            }
          }
        },
        onNginxSetup: (p) async {
          Navigator.pop(ctx);
          await _setupNginx(p);
        },
        onNginxRemove: (p) async {
          Navigator.pop(ctx);
          await _removeNginx(p);
        },
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(odooProjectsProvider);
    final isGridView = asyncState.valueOrNull?.gridView ?? true;

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
                  ref.read(odooProjectsProvider.notifier).toggleGridView();
                },
                icon: Icon(isGridView ? Icons.view_list : Icons.grid_view),
                tooltip: isGridView
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
                onPressed: () =>
                    ref.read(odooProjectsProvider.notifier).reload(),
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
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          asyncState.when(
            loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator())),
            error: (err, _) => Expanded(
              child: Center(child: Text(err.toString())),
            ),
            data: (state) {
              final projects = state.projects;
              final filtered = _applyFilter(projects);
              if (projects.isEmpty) {
                return Expanded(
                  child: Center(child: Text(context.l10n.projectsEmpty)),
                );
              }
              if (filtered.isEmpty) {
                return Expanded(
                  child: Center(child: Text(context.l10n.projectsNoMatch)),
                );
              }
              return Expanded(
                child: isGridView
                    ? _buildGridView(filtered)
                    : _buildListView(filtered),
              );
            },
          ),
        ],
      ),
    );
  }
}
