import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/workspace_info.dart';
import '../../services/nginx_service.dart';
import '../../services/platform_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/nginx_setup_dialog.dart';
import '../../widgets/vscode_install_dialog.dart';
import '../home_screen.dart';
import '../odoo_projects/odoo_projects_screen.dart';
import 'import_workspace_dialog.dart';
import 'simple_git_commit_dialog.dart';
import 'simple_git_pull_dialog.dart';
import 'switch_branch_dialog.dart';

// thay đổi để test

class OtherProjectsScreen extends StatefulWidget {
  const OtherProjectsScreen({super.key});

  @override
  State<OtherProjectsScreen> createState() => _OtherProjectsScreenState();
}

class _OtherProjectsScreenState extends State<OtherProjectsScreen> {
  List<WorkspaceInfo> _workspaces = [];
  List<WorkspaceInfo> _filtered = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  String _filterType = '';
  final Map<String, String> _branches = {};
  final Map<String, int> _changedCount = {}; // path → number of changed files
  final Map<String, int> _behindCount = {}; // path → commits behind remote

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final json = await StorageService.loadWorkspaces();
    final workspaces = json.map((j) => WorkspaceInfo.fromJson(j)).toList();
    workspaces.sort((a, b) {
      if (a.favourite != b.favourite) return a.favourite ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    setState(() {
      _workspaces = workspaces;
      _applyFilter();
      _loading = false;
    });
    _loadBranches(workspaces);
  }

  Future<void> _loadBranchStatus(String path) async {
    if (!Directory(p.join(path, '.git')).existsSync()) return;
    try {
      // Current branch
      final result = await Process.run(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: path,
        runInShell: true,
      );
      if (result.exitCode == 0 && mounted) {
        final branch = (result.stdout as String).trim();
        if (branch.isNotEmpty) {
          setState(() => _branches[path] = branch);
        }
      }

      // Changed files count
      final statusResult = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: path,
        runInShell: true,
      );
      if (statusResult.exitCode == 0 && mounted) {
        final lines = (statusResult.stdout as String)
            .trimRight()
            .split('\n')
            .where((l) => l.isNotEmpty)
            .length;
        setState(() => _changedCount[path] = lines);
      }

      // Behind remote count (không fetch — chỉ check local cache)
      final behindResult = await Process.run(
        'git',
        ['rev-list', '--count', 'HEAD..@{upstream}'],
        workingDirectory: path,
        runInShell: true,
      );
      if (behindResult.exitCode == 0 && mounted) {
        final count = int.tryParse((behindResult.stdout as String).trim()) ?? 0;
        setState(() => _behindCount[path] = count);
      }
    } catch (_) {}
  }

  Future<void> _loadBranches(List<WorkspaceInfo> workspaces) async {
    for (final ws in workspaces) {
      await _loadBranchStatus(ws.path);
    }
  }

  void _switchBranch(WorkspaceInfo ws) {
    AppDialog.show(
      context: context,
      builder: (ctx) => SwitchBranchDialog(
        projectPath: ws.path,
        currentBranch: _branches[ws.path] ?? '',
        branchColor: _branchColor,
        onSwitched: (branch) {
          setState(() => _branches[ws.path] = branch);
        },
      ),
    ).then((_) {
      if (mounted) {
        _loadBranchStatus(ws.path);
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

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    _filtered = _workspaces.where((w) {
      final matchSearch =
          q.isEmpty ||
          w.name.toLowerCase().contains(q) ||
          w.path.toLowerCase().contains(q) ||
          w.type.toLowerCase().contains(q) ||
          w.description.toLowerCase().contains(q);
      final matchType =
          _filterType.isEmpty || w.type.toLowerCase() == _filterType;
      return matchSearch && matchType;
    }).toList();
  }

  Set<String> get _allTypes =>
      _workspaces.map((w) => w.type).where((t) => t.isNotEmpty).toSet();

  Future<void> _importWorkspace() async {
    final result = await AppDialog.show<WorkspaceInfo>(
      context: context,
      builder: (ctx) => const ImportWorkspaceDialog(),
    );
    if (result != null) {
      await StorageService.addWorkspace(result.toJson());
      await _load();
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
      await StorageService.removeWorkspace(workspace.path);
      await StorageService.addWorkspace(updated.toJson());
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
    final installed = await PlatformService.isVscodeInstalled();
    if (!installed) {
      if (!mounted) return;
      _showVscodeInstallDialog();
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

  void _showVscodeInstallDialog() {
    AppDialog.show(context: context, builder: (ctx) => const VscodeInstallDialog());
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
        _loadBranchStatus(ws.path);
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
        _loadBranchStatus(ws.path);
      }
    });
  }

  Future<void> _linkNginx(WorkspaceInfo ws) async {
    final nginx = await NginxService.loadSettings();
    final confDir = (nginx['confDir'] ?? '').toString();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (confDir.isEmpty || suffix.isEmpty) {
      HomeScreen.navigateToSettings(settingsTab: 4);
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

    final updated = ws.copyWith(nginxSubdomain: () => selected);
    await StorageService.removeWorkspace(ws.path);
    await StorageService.addWorkspace(updated.toJson());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.nginxLinked('$selected$dotSuffix')),
        ),
      );
    }
    await _load();
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
    final result = await AppDialog.show<({String subdomain, int? port})>(
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
      await StorageService.removeWorkspace(ws.path);
      await StorageService.addWorkspace(updated.toJson());
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
      await StorageService.removeWorkspace(ws.path);
      await StorageService.addWorkspace(updated.toJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.nginxRemoveSuccess('$sub$dotSuffix')),
          ),
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

  Future<void> _toggleFavourite(WorkspaceInfo ws) async {
    final updated = ws.copyWith(favourite: !ws.favourite);
    await StorageService.removeWorkspace(ws.path);
    await StorageService.addWorkspace(updated.toJson());
    await _load();
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
      // Cleanup nginx config if workspace has one
      if (workspace.hasNginx) {
        try {
          final sub = workspace.nginxSubdomain!;
          await NginxService.removeNginx(sub);
        } catch (_) {}
      }
      await StorageService.removeWorkspace(workspace.path);
      await _load();
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

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _filtered.length,
      itemBuilder: (context, index) {
        final ws = _filtered[index];
        final exists = Directory(ws.path).existsSync();

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
                      exists ? _iconForType(ws.type) : Icons.folder_off,
                      color: exists ? _colorForType(ws.type) : Colors.grey,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        ws.name,
                        style: const TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (ws.type.isNotEmpty)
                      Chip(
                        label: Text(ws.type),
                        avatar: Icon(
                          _iconForType(ws.type),
                          size: AppIconSize.md,
                          color: _colorForType(ws.type),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (ws.description.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Chip(
                          label: Text(
                            ws.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                          avatar: const Icon(
                            Icons.description,
                            size: AppIconSize.md,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                    if (_branches.containsKey(ws.path)) ...[
                      const SizedBox(width: AppSpacing.sm),
                      InkWell(
                        onTap: () => _switchBranch(ws),
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(8),
                        child: Chip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _branches[ws.path]!,
                                  style: TextStyle(
                                    color: _branchColor(_branches[ws.path]!),
                                  ),
                                ),
                                if ((_changedCount[ws.path] ?? 0) > 0) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    '${_changedCount[ws.path]}↑',
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                                if ((_behindCount[ws.path] ?? 0) > 0) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    '${_behindCount[ws.path]}↓',
                                    style: const TextStyle(
                                      color: Colors.cyan,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            avatar: Icon(
                              Icons.account_tree,
                              size: AppIconSize.md,
                              color: _branchColor(_branches[ws.path]!),
                            ),
                            backgroundColor: _branchColor(
                              _branches[ws.path]!,
                            ).withValues(alpha: 0.1),
                            visualDensity: VisualDensity.compact,
                          ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  ws.path,
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
                      onPressed: () => _toggleFavourite(ws),
                      icon: Icon(
                        ws.favourite ? Icons.star : Icons.star_border,
                        color: ws.favourite ? Colors.amber : null,
                      ),
                      tooltip: ws.favourite
                          ? context.l10n.unfavourite
                          : context.l10n.favourite,
                    ),
                    if (exists) ...[
                      IconButton(
                        onPressed: () => _runGitPull(ws),
                        icon: const Icon(Icons.sync),
                        tooltip: context.l10n.gitPull,
                      ),
                      IconButton(
                        onPressed: () => _runGitCommit(ws),
                        icon: const Icon(Icons.commit),
                        tooltip: context.l10n.gitCommit,
                      ),
                      IconButton(
                        onPressed: () => _openInVscode(ws.path),
                        icon: const Icon(Icons.code),
                        tooltip: context.l10n.openInVscode,
                      ),
                      IconButton(
                        onPressed: () => _openInFileManager(ws.path),
                        icon: const Icon(Icons.folder_open),
                        tooltip: context.l10n.openFolder,
                      ),
                    ],
                    IconButton(
                      onPressed: () => _editWorkspace(ws),
                      icon: const Icon(Icons.edit),
                      tooltip: context.l10n.edit,
                    ),
                    if (ws.hasNginx)
                      IconButton(
                        onPressed: () => _removeNginx(ws),
                        icon: const Icon(Icons.dns, color: Colors.green),
                        tooltip: context.l10n.nginxRemove,
                      )
                    else
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.dns),
                        tooltip: context.l10n.nginxSetup,
                        onSelected: (v) {
                          if (v == 'setup') _setupNginx(ws);
                          if (v == 'link') _linkNginx(ws);
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'setup',
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: AppIconSize.md),
                                const SizedBox(width: AppSpacing.sm),
                                Text(context.l10n.nginxSetup),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'link',
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: AppIconSize.md),
                                const SizedBox(width: AppSpacing.sm),
                                Text(context.l10n.nginxLink),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _remove(ws),
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
            final ws = _filtered[index];
            final exists = Directory(ws.path).existsSync();
            final color = exists ? _colorForType(ws.type) : Colors.grey;

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: ws.description.isNotEmpty ? ws.description : ws.path,
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  onTap: exists ? () => _openInVscode(ws.path) : null,
                  onSecondaryTapDown: (details) =>
                      _showGridContextMenu(details.globalPosition, ws, exists),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Top row: type (left) + star (right)
                        Stack(
                          children: [
                            if (ws.type.isNotEmpty)
                              Align(
                                alignment: Alignment.topLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: AppRadius.smallBorderRadius,
                                  ),
                                  child: Text(
                                    ws.type,
                                    style: TextStyle(
                                      fontSize: AppFontSize.xs,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                onPressed: () => _toggleFavourite(ws),
                                icon: Icon(
                                  ws.favourite ? Icons.star : Icons.star_border,
                                  size: AppIconSize.lg,
                                  color: ws.favourite
                                      ? Colors.amber
                                      : Colors.grey.shade600,
                                ),
                                tooltip: ws.favourite
                                    ? context.l10n.unfavourite
                                    : context.l10n.favourite,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Branch badge
                        if (_branches.containsKey(ws.path)) ...[
                          InkWell(
                            onTap: () => _switchBranch(ws),
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: AppRadius.smallBorderRadius,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _branchColor(
                                  _branches[ws.path]!,
                                ).withValues(alpha: 0.15),
                                borderRadius: AppRadius.smallBorderRadius,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((_changedCount[ws.path] ?? 0) >
                                      0) ...[
                                    Text(
                                      '${_changedCount[ws.path]}↑',
                                      style: const TextStyle(
                                        fontSize: AppFontSize.xs,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: AppSpacing.xs,
                                    ),
                                  ],
                                  if ((_behindCount[ws.path] ?? 0) >
                                      0) ...[
                                    Text(
                                      '${_behindCount[ws.path]}↓',
                                      style: const TextStyle(
                                        fontSize: AppFontSize.xs,
                                        color: Colors.cyan,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: AppSpacing.xs,
                                    ),
                                  ],
                                  Flexible(
                                    child: Text(
                                      _branches[ws.path]!,
                                      style: TextStyle(
                                        fontSize: AppFontSize.xs,
                                        fontFamily: 'monospace',
                                        color: _branchColor(
                                          _branches[ws.path]!,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        // Project name - prominent
                        Text(
                          ws.name,
                          style: TextStyle(
                            fontSize: nameSize,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        // Quick action buttons
                        if (exists)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: AppSpacing.lg,
                            children: [
                              _gridBtn(
                                icon: Icons.sync,
                                tooltip: context.l10n.gitPull,
                                onPressed: () => _runGitPull(ws),
                                iconSize: btnSize,
                                boxSize: btnBox,
                              ),
                              _gridBtn(
                                icon: Icons.commit,
                                tooltip: context.l10n.gitCommit,
                                onPressed: () => _runGitCommit(ws),
                                iconSize: btnSize,
                                boxSize: btnBox,
                              ),
                              _gridBtn(
                                icon: Icons.folder_open,
                                tooltip: context.l10n.openFolder,
                                onPressed: () => _openInFileManager(ws.path),
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
    Offset position,
    WorkspaceInfo ws,
    bool exists,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'favourite',
          child: Row(
            children: [
              Icon(
                ws.favourite ? Icons.star : Icons.star_border,
                size: AppIconSize.md,
                color: ws.favourite ? Colors.amber : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                ws.favourite
                    ? context.l10n.unfavourite
                    : context.l10n.favourite,
              ),
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
        if (ws.hasNginx)
          PopupMenuItem(
            value: 'nginx_remove',
            child: Row(
              children: [
                const Icon(
                  Icons.dns,
                  size: AppIconSize.md,
                  color: Colors.green,
                ),
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
              Text(
                context.l10n.removeFromList,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
    if (result == null) return;
    switch (result) {
      case 'favourite':
        _toggleFavourite(ws);
      case 'git_pull':
        _runGitPull(ws);
      case 'git_commit':
        _runGitCommit(ws);
      case 'vscode':
        _openInVscode(ws.path);
      case 'folder':
        _openInFileManager(ws.path);
      case 'nginx_setup':
        _setupNginx(ws);
      case 'nginx_link':
        _linkNginx(ws);
      case 'nginx_remove':
        _removeNginx(ws);
      case 'edit':
        _editWorkspace(ws);
      case 'delete':
        _remove(ws);
    }
  }

  Widget _gridBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required double iconSize,
    required double boxSize,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      color: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: boxSize, minHeight: boxSize),
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
                onPressed: () {
                  setState(
                    () => OdooProjectsScreen.gridView = !OdooProjectsScreen.gridView,
                  );
                  OdooProjectsScreen.saveViewPreference();
                },
                icon: Icon(
                  OdooProjectsScreen.gridView ? Icons.view_list : Icons.grid_view,
                ),
                tooltip: OdooProjectsScreen.gridView
                    ? context.l10n.wsViewList
                    : context.l10n.wsViewGrid,
              ),
              FilledButton.icon(
                onPressed: _importWorkspace,
                icon: const Icon(Icons.add),
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
                              setState(() => _applyFilter());
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() => _applyFilter()),
                ),
              ),
              if (_allTypes.isNotEmpty) ...[
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
                      _applyFilter();
                    });
                  },
                  itemBuilder: (ctx) => [
                    if (_filterType.isNotEmpty)
                      PopupMenuItem(
                        value: '',
                        child: Text(context.l10n.wsShowAll),
                      ),
                    ..._allTypes.map(
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
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_workspaces.isEmpty)
            Expanded(child: Center(child: Text(context.l10n.wsEmpty)))
          else if (_filtered.isEmpty)
            Expanded(child: Center(child: Text(context.l10n.wsNoMatch)))
          else
            Expanded(
              child: OdooProjectsScreen.gridView
                  ? _buildGridView()
                  : _buildListView(),
            ),
        ],
      ),
    );
  }
}
