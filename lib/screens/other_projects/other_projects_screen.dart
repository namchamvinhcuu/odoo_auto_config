import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/providers/odoo_projects_provider.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'package:odoo_auto_config/widgets/clone_repository_dialog.dart';
import 'package:odoo_auto_config/widgets/nginx_setup_dialog.dart';
import 'package:odoo_auto_config/widgets/vscode_install_dialog.dart';
import 'package:odoo_auto_config/screens/home_screen.dart';
import 'import_workspace_dialog.dart';
import 'simple_git_commit_dialog.dart';
import 'simple_git_pull_dialog.dart';
import 'other_project_grid_view.dart';
import 'other_project_list_view.dart';
import 'switch_branch_dialog.dart';

class OtherProjectsScreen extends ConsumerStatefulWidget {
  const OtherProjectsScreen({super.key});

  @override
  ConsumerState<OtherProjectsScreen> createState() =>
      _OtherProjectsScreenState();
}

class _OtherProjectsScreenState extends ConsumerState<OtherProjectsScreen> {
  static const _favKey = 'otherProjectsFavouritesOnly';

  final _searchController = TextEditingController();
  String _filterType = '';
  String? _selectedPath;
  bool _favouritesOnly = false;

  @override
  void initState() {
    super.initState();
    _loadFavouritesOnly();
  }

  Future<void> _loadFavouritesOnly() async {
    final settings = await StorageService.loadSettings();
    final value = settings[_favKey] as bool? ?? false;
    if (mounted && value != _favouritesOnly) {
      setState(() => _favouritesOnly = value);
    }
  }

  Future<void> _setFavouritesOnly(bool value) async {
    setState(() => _favouritesOnly = value);
    await StorageService.updateSettings((settings) {
      settings[_favKey] = value;
    });
  }

  void _switchBranch(WorkspaceInfo ws) {
    final branches =
        ref.read(otherProjectsProvider).valueOrNull?.branches ?? {};
    AppDialog.show(
      context: context,
      builder: (ctx) => SwitchBranchDialog(
        projectPath: ws.path,
        currentBranch: branches[ws.path] ?? '',
        branchColor: _branchColor,
        onSwitched: (branch) {
          ref.read(otherProjectsProvider.notifier).loadBranchStatus(ws.path);
        },
      ),
    ).then((_) {
      if (mounted) {
        ref.read(otherProjectsProvider.notifier).loadBranchStatus(ws.path);
      }
    });
  }

  Color _branchColor(String branch) {
    final b = branch.toLowerCase();
    if (b == 'main' || b == 'master') return Colors.green;
    if (b == 'dev' || b == 'develop' || b.startsWith('dev')) {
      return Colors.orange;
    }
    if (b.startsWith('feature') || b.startsWith('feat')) return Colors.blue;
    if (b.startsWith('hotfix') || b.startsWith('fix')) return Colors.red;
    return Colors.cyan;
  }

  List<WorkspaceInfo> _applyFilter(List<WorkspaceInfo> workspaces) {
    final q = _searchController.text.toLowerCase();
    return workspaces.where((w) {
      final matchSearch =
          q.isEmpty ||
          w.name.toLowerCase().contains(q) ||
          w.path.toLowerCase().contains(q) ||
          w.type.toLowerCase().contains(q) ||
          w.description.toLowerCase().contains(q);
      final matchType =
          _filterType.isEmpty || w.type.toLowerCase() == _filterType;
      final matchFavourite = !_favouritesOnly || w.favourite;
      return matchSearch && matchType && matchFavourite;
    }).toList();
  }

  Set<String> _allTypes(List<WorkspaceInfo> workspaces) =>
      workspaces.map((w) => w.type).where((t) => t.isNotEmpty).toSet();

  Future<void> _importWorkspace() async {
    final result = await AppDialog.show<WorkspaceInfo>(
      context: context,
      builder: (ctx) => const ImportWorkspaceDialog(),
    );
    if (result != null) {
      await ref.read(otherProjectsProvider.notifier).addWorkspace(result);
    }
  }

  Future<void> _cloneRepository() async {
    final result = await AppDialog.show<CloneRepositoryResult>(
      context: context,
      builder: (ctx) => const CloneRepositoryDialog(),
    );
    if (result != null) {
      final workspace = WorkspaceInfo(
        name: result.repoName,
        path: result.targetDir,
        type: result.detectedType,
        description: result.description,
        createdAt: DateTime.now().toIso8601String(),
      );
      await ref.read(otherProjectsProvider.notifier).addWorkspace(workspace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloned and added "${workspace.name}"')),
        );
      }
    }
  }

  Future<void> _editWorkspace(WorkspaceInfo workspace) async {
    final result = await AppDialog.show<WorkspaceInfo>(
      context: context,
      builder: (ctx) => ImportWorkspaceDialog(existing: workspace),
    );
    if (result != null) {
      // Preserve favourite and nginxSubdomain from original
      final updated = result.copyWith(
        favourite: workspace.favourite,
        nginxSubdomain: workspace.nginxSubdomain != null
            ? () => workspace.nginxSubdomain
            : null,
      );
      await ref
          .read(otherProjectsProvider.notifier)
          .updateWorkspace(workspace, updated);
    }
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
      _showVscodeInstallDialog();
      return;
    }
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [
          '-a',
          'Visual Studio Code',
          path,
        ], runInShell: true);
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

  Future<void> _openInVisualStudio(String path) async {
    final slnFiles = PlatformService.findSlnFiles(path);
    if (slnFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noSlnFileFound)),
      );
      return;
    }

    String slnPath;
    if (slnFiles.length == 1) {
      slnPath = slnFiles.first;
    } else {
      // Cho user chọn khi có nhiều .sln files
      final selected = await AppDialog.show<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Text(context.l10n.selectSlnFile),
              const Spacer(),
              AppDialog.closeButton(ctx),
            ],
          ),
          content: SizedBox(
            width: AppDialog.widthSm,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: slnFiles
                  .map(
                    (f) => ListTile(
                      leading: const Icon(Icons.description),
                      title: Text(p.basename(f)),
                      subtitle: Text(f, style: const TextStyle(fontSize: AppFontSize.xs)),
                      onTap: () => Navigator.pop(ctx, f),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      );
      if (selected == null) return;
      slnPath = selected;
    }

    final success = await PlatformService.openInVisualStudio(slnPath);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpenVisualStudio)),
      );
    }
  }

  void _showVscodeInstallDialog() {
    AppDialog.show(
      context: context,
      builder: (ctx) => const VscodeInstallDialog(),
    );
  }

  void _runGitPull(WorkspaceInfo ws) {
    // Check if .git exists
    final gitDir = Directory(p.join(ws.path, '.git'));
    if (!gitDir.existsSync()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.gitPullNotARepo)));
      return;
    }
    AppDialog.show(
      context: context,
      builder: (ctx) =>
          SimpleGitPullDialog(projectName: ws.name, projectPath: ws.path),
    ).then((_) {
      if (mounted) {
        ref.read(otherProjectsProvider.notifier).loadBranchStatus(ws.path);
      }
    });
  }

  void _runGitCommit(WorkspaceInfo ws) {
    final gitDir = Directory(p.join(ws.path, '.git'));
    if (!gitDir.existsSync()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.gitPullNotARepo)));
      return;
    }
    AppDialog.show(
      context: context,
      builder: (ctx) =>
          SimpleGitCommitDialog(projectName: ws.name, projectPath: ws.path),
    ).then((_) {
      if (mounted) {
        ref.read(otherProjectsProvider.notifier).loadBranchStatus(ws.path);
      }
    });
  }

  Future<void> _setupNginx(WorkspaceInfo ws) async {
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
        initialSubdomain: NginxService.sanitizeSubdomain(ws.name),
        domainSuffix: suffix,
        initialPort: ws.port,
        showPort: true,
        existingSubdomains: existingSubs,
        usedPorts: usedPorts,
      ),
    );
    if (result == null) return;

    if (result.isLink) {
      try {
        final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
        final updated = ws.copyWith(nginxSubdomain: () => result.subdomain);
        await ref
            .read(otherProjectsProvider.notifier)
            .updateWorkspace(ws, updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.nginxLinked('${result.subdomain}$dotSuffix'),
              ),
            ),
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

    final port = result.port ?? ws.port;
    if (port == null || port <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.nginxNoPort)));
      }
      return;
    }

    try {
      final domain = await NginxService.setupGeneric(
        subdomain: result.subdomain,
        port: port,
      );
      // Save subdomain and port to workspace
      final updated = ws.copyWith(
        nginxSubdomain: () => result.subdomain,
        port: result.port ?? port,
      );
      await ref
          .read(otherProjectsProvider.notifier)
          .updateWorkspace(ws, updated);
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

  Future<void> _removeNginx(WorkspaceInfo ws) async {
    final subdomain = NginxService.sanitizeSubdomain(ws.name);
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(context.l10n.nginxRemove),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
        content: Text(context.l10n.nginxConfirmRemove(ws.name)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.l10n.nginxRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final nginx = await NginxService.loadSettings();
      final suffix = (nginx['domainSuffix'] ?? '').toString();
      final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
      final sub = ws.nginxSubdomain ?? subdomain;
      await NginxService.removeNginx(sub);
      // Clear subdomain from workspace
      final updated = ws.copyWith(nginxSubdomain: () => null);
      await ref
          .read(otherProjectsProvider.notifier)
          .updateWorkspace(ws, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.nginxRemoveSuccess('$sub$dotSuffix')),
          ),
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

  Future<void> _toggleFavourite(WorkspaceInfo ws) async {
    await ref.read(otherProjectsProvider.notifier).toggleFavourite(ws);
  }

  Future<void> _remove(WorkspaceInfo workspace) async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(context.l10n.wsDeleteTitle),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
        content: Text(context.l10n.wsDeleteConfirm(workspace.name)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(otherProjectsProvider.notifier).deleteWorkspace(workspace);
    }
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'flutter':
        return Icons.flutter_dash;
      case 'react':
      case 'reactjs':
      case 'nextjs':
      case 'next.js':
        return Icons.web;
      case 'dotnet':
      case '.net':
      case 'c#':
        return Icons.developer_mode;
      case 'python':
      case 'odoo':
        return Icons.code;
      case 'rust':
      case 'go':
      case 'java':
        return Icons.terminal;
      default:
        return Icons.folder;
    }
  }

  Widget _buildListView(
    List<WorkspaceInfo> filtered,
    OtherProjectsState state,
  ) {
    return OtherProjectListView(
      workspaces: filtered,
      state: state,
      onToggleFavourite: _toggleFavourite,
      onGitPull: _runGitPull,
      onGitCommit: _runGitCommit,
      onOpenInVscode: (ws) => _openInVscode(ws.path),
      onOpenInVisualStudio: (ws) => _openInVisualStudio(ws.path),
      onOpenInFileManager: (ws) => _openInFileManager(ws.path),
      onEdit: _editWorkspace,
      onSetupNginx: _setupNginx,
      onRemoveNginx: _removeNginx,
      onRemove: _remove,
      onSwitchBranch: _switchBranch,
      branchColor: _branchColor,
      iconForType: _iconForType,
      colorForType: _colorForType,
    );
  }

  Widget _buildGridView(
    List<WorkspaceInfo> filtered,
    OtherProjectsState state,
  ) {
    return OtherProjectGridView(
      workspaces: filtered,
      state: state,
      selectedPath: _selectedPath,
      onToggleFavourite: _toggleFavourite,
      onGitPull: _runGitPull,
      onGitCommit: _runGitCommit,
      onSelect: (ws) => setState(() => _selectedPath = _selectedPath == ws.path ? null : ws.path),
      onOpenInVscode: (ws) => _openInVscode(ws.path),
      onOpenInVisualStudio: (ws) => _openInVisualStudio(ws.path),
      onOpenInFileManager: (ws) => _openInFileManager(ws.path),
      onEdit: _editWorkspace,
      onSetupNginx: _setupNginx,
      onRemoveNginx: _removeNginx,
      onRemove: _remove,
      onSwitchBranch: _switchBranch,
      branchColor: _branchColor,
      colorForType: _colorForType,
    );
  }

  Color _colorForType(String type) {
    switch (type.toLowerCase()) {
      case 'flutter':
        return Colors.blue;
      case 'react':
      case 'reactjs':
        return Colors.cyan;
      case 'nextjs':
      case 'next.js':
        return Colors.grey;
      case 'dotnet':
      case '.net':
      case 'c#':
        return Colors.purple;
      case 'python':
        return Colors.amber;
      case 'odoo':
        return Colors.deepPurple;
      case 'rust':
        return Colors.orange;
      case 'go':
        return Colors.teal;
      case 'java':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(otherProjectsProvider);
    final isGridView =
        ref.watch(odooProjectsProvider).valueOrNull?.gridView ?? true;

    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspaces, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(
                context.l10n.wsTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    ref.read(odooProjectsProvider.notifier).toggleGridView(),
                icon: Icon(isGridView ? Icons.view_list : Icons.grid_view),
                tooltip: isGridView
                    ? context.l10n.wsViewList
                    : context.l10n.wsViewGrid,
              ),
              FilledButton.icon(
                onPressed: _importWorkspace,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.import_),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: _cloneRepository,
                icon: const Icon(Icons.download),
                label: const Text('Clone Repo'),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: () =>
                    ref.read(otherProjectsProvider.notifier).reload(),
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.refresh,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.wsSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Search + type filter
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: context.l10n.wsSearchHint,
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
              ),
              if (asyncState.valueOrNull != null &&
                  _allTypes(asyncState.valueOrNull!.workspaces).isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                PopupMenuButton<String>(
                  icon: Badge(
                    isLabelVisible: _filterType.isNotEmpty,
                    child: const Icon(Icons.filter_list),
                  ),
                  tooltip: context.l10n.wsFilterByType,
                  onSelected: (type) {
                    setState(() {
                      _filterType = _filterType == type ? '' : type;
                    });
                  },
                  itemBuilder: (ctx) => [
                    if (_filterType.isNotEmpty)
                      PopupMenuItem(
                        value: '',
                        child: Text(context.l10n.wsShowAll),
                      ),
                    ..._allTypes(asyncState.valueOrNull!.workspaces).map(
                      (t) => PopupMenuItem(
                        value: t.toLowerCase(),
                        child: Row(
                          children: [
                            Icon(
                              _iconForType(t),
                              size: AppIconSize.md,
                              color: _colorForType(t),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(t),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: () => _setFavouritesOnly(!_favouritesOnly),
                icon: Icon(
                  _favouritesOnly ? Icons.star : Icons.star_border,
                  color: _favouritesOnly ? Colors.amber : null,
                ),
                tooltip: context.l10n.showFavouritesOnly,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          asyncState.when(
            loading: () => const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) =>
                Expanded(child: Center(child: Text(err.toString()))),
            data: (state) {
              final workspaces = state.workspaces;
              final filtered = _applyFilter(workspaces);
              if (workspaces.isEmpty) {
                return Expanded(
                  child: Center(child: Text(context.l10n.wsEmpty)),
                );
              }
              if (filtered.isEmpty) {
                return Expanded(
                  child: Center(child: Text(context.l10n.wsNoMatch)),
                );
              }
              return Expanded(
                child: isGridView
                    ? _buildGridView(filtered, state)
                    : _buildListView(filtered, state),
              );
            },
          ),
        ],
      ),
    );
  }
}
