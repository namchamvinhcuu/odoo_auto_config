import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/workspace_info.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/storage_service.dart';
import '../widgets/nginx_setup_dialog.dart';
import '../widgets/vscode_install_dialog.dart';
import 'home_screen.dart';
import 'projects_screen.dart';

// thay đổi để test

class WorkspacesScreen extends StatefulWidget {
  const WorkspacesScreen({super.key});

  @override
  State<WorkspacesScreen> createState() => _WorkspacesScreenState();
}

class _WorkspacesScreenState extends State<WorkspacesScreen> {
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
    showDialog(
      context: context,
      builder: (ctx) => _SwitchBranchDialog(
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
    final result = await showDialog<WorkspaceInfo>(
      context: context,
      builder: (ctx) => const _ImportWorkspaceDialog(),
    );
    if (result != null) {
      await StorageService.addWorkspace(result.toJson());
      await _load();
    }
  }

  Future<void> _editWorkspace(WorkspaceInfo workspace) async {
    final result = await showDialog<WorkspaceInfo>(
      context: context,
      builder: (ctx) => _ImportWorkspaceDialog(existing: workspace),
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
    showDialog(context: context, builder: (ctx) => const VscodeInstallDialog());
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
    showDialog(
      context: context,
      builder: (ctx) =>
          _SimpleGitPullDialog(projectName: ws.name, projectPath: ws.path),
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
    showDialog(
      context: context,
      builder: (ctx) =>
          _SimpleGitCommitDialog(projectName: ws.name, projectPath: ws.path),
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
    final result = await showDialog<({String subdomain, int? port})>(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.nginxRemove),
        content: Text(context.l10n.nginxConfirmRemove(ws.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.wsDeleteTitle),
        content: Text(context.l10n.wsDeleteConfirm(workspace.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
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
        final typeSize = cellWidth >= 200 ? AppFontSize.md : AppFontSize.sm;
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
                        // Top row: branch (left) + star (right)
                        Stack(
                          children: [
                            if (_branches.containsKey(ws.path))
                              Align(
                                alignment: Alignment.topLeft,
                                child: InkWell(
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
                                        borderRadius:
                                            AppRadius.smallBorderRadius,
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
                        // Project type as accent badge
                        if (ws.type.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: AppRadius.mediumBorderRadius,
                            ),
                            child: Text(
                              ws.type,
                              style: TextStyle(
                                fontSize: typeSize,
                                fontWeight: FontWeight.w600,
                                color: color,
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
                    () => ProjectsScreen.gridView = !ProjectsScreen.gridView,
                  );
                  ProjectsScreen.saveViewPreference();
                },
                icon: Icon(
                  ProjectsScreen.gridView ? Icons.view_list : Icons.grid_view,
                ),
                tooltip: ProjectsScreen.gridView
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
              child: ProjectsScreen.gridView
                  ? _buildGridView()
                  : _buildListView(),
            ),
        ],
      ),
    );
  }
}

// ── Import Workspace Dialog ──

const _presetTypes = [
  'Flutter',
  'React',
  'NextJS',
  'Odoo',
  'Python',
  '.NET',
  'Rust',
  'Go',
  'Java',
];

class _ImportWorkspaceDialog extends StatefulWidget {
  final WorkspaceInfo? existing;

  const _ImportWorkspaceDialog({this.existing});

  @override
  State<_ImportWorkspaceDialog> createState() => _ImportWorkspaceDialogState();
}

class _ImportWorkspaceDialogState extends State<_ImportWorkspaceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _typeController;
  late final TextEditingController _portController;
  late String _workspacePath;
  late String _description;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _typeController = TextEditingController(text: e?.type ?? '');
    _portController = TextEditingController(
      text: e?.port != null ? '${e!.port}' : '',
    );
    _workspacePath = e?.path ?? '';
    _description = e?.description ?? '';
  }

  Future<void> _pickDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
        dialogTitle: context.l10n.wsSelectDirectory,
      );
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: context.l10n.wsSelectDirectory,
      );
    }
    if (path == null) return;

    setState(() {
      _workspacePath = path!;
      if (_nameController.text.isEmpty) {
        _nameController.text = path.split('/').last.split('\\').last;
      }
    });

    // Auto-detect type from project files
    _autoDetectType(path);
  }

  Future<void> _autoDetectType(String dirPath) async {
    if (_typeController.text.isNotEmpty) return;

    final markers = {
      'pubspec.yaml': 'Flutter',
      'package.json': '', // need further check
      '.csproj': '.NET',
      'Cargo.toml': 'Rust',
      'go.mod': 'Go',
      'pom.xml': 'Java',
      'build.gradle': 'Java',
      'requirements.txt': 'Python',
      'setup.py': 'Python',
      'pyproject.toml': 'Python',
    };

    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    for (final entry in markers.entries) {
      if (await File('$dirPath/${entry.key}').exists()) {
        if (entry.key == 'package.json') {
          // Check for next.config
          if (await File('$dirPath/next.config.js').exists() ||
              await File('$dirPath/next.config.mjs').exists() ||
              await File('$dirPath/next.config.ts').exists()) {
            setState(() => _typeController.text = 'NextJS');
          } else {
            setState(() => _typeController.text = 'React');
          }
        } else if (entry.value == 'Python') {
          // Check if it's Odoo
          if (await File('$dirPath/odoo-bin').exists() ||
              await File('$dirPath/odoo.conf').exists() ||
              await Directory('$dirPath/addons').exists()) {
            setState(() => _typeController.text = 'Odoo');
          } else {
            setState(() => _typeController.text = entry.value);
          }
        } else {
          setState(() => _typeController.text = entry.value);
        }
        return;
      }
    }

    // Check .csproj pattern (any *.csproj file)
    try {
      final files = await dir.list().toList();
      for (final f in files) {
        if (f.path.endsWith('.csproj') || f.path.endsWith('.sln')) {
          setState(() => _typeController.text = '.NET');
          return;
        }
      }
    } catch (_) {}
  }

  void _save() {
    if (_workspacePath.isEmpty || _nameController.text.isEmpty) return;

    final portText = _portController.text.trim();
    final workspace = WorkspaceInfo(
      name: _nameController.text.trim(),
      path: _workspacePath,
      type: _typeController.text.trim(),
      description: _description,
      createdAt: widget.existing?.createdAt ?? DateTime.now().toIso8601String(),
      port: portText.isNotEmpty ? int.tryParse(portText) : null,
    );

    Navigator.pop(context, workspace);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing != null ? context.l10n.wsEdit : context.l10n.wsImport,
      ),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Directory picker
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _workspacePath),
                      decoration: InputDecoration(
                        labelText: context.l10n.wsDirectory,
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
              const SizedBox(height: AppSpacing.lg),

              // Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.wsName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Type with presets
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _typeController,
                      decoration: InputDecoration(
                        labelText: context.l10n.wsType,
                        hintText: context.l10n.wsTypeHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                    tooltip: context.l10n.wsSelectType,
                    onSelected: (type) {
                      setState(() => _typeController.text = type);
                    },
                    itemBuilder: (ctx) => _presetTypes
                        .map((t) => PopupMenuItem(value: t, child: Text(t)))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Description
              TextField(
                controller: TextEditingController(text: _description),
                onChanged: (v) => _description = v,
                decoration: InputDecoration(
                  labelText: context.l10n.descriptionOptional,
                  hintText: context.l10n.wsDescriptionHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Port (optional, for nginx)
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: context.l10n.wsPort,
                  hintText: context.l10n.wsPortHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed:
              (_workspacePath.isNotEmpty && _nameController.text.isNotEmpty)
              ? _save
              : null,
          child: Text(
            widget.existing != null ? context.l10n.save : context.l10n.import_,
          ),
        ),
      ],
    );
  }
}

// ── Simple Git Pull dialog (single repo, just `git pull`) ──

class _SimpleGitPullDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const _SimpleGitPullDialog({
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<_SimpleGitPullDialog> createState() => _SimpleGitPullDialogState();
}

class _SimpleGitPullDialogState extends State<_SimpleGitPullDialog> {
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    31: Color(0xFFCD3131),
    32: Color(0xFF0DBC79),
    33: Color(0xFFE5E510),
    34: Color(0xFF2472C8),
    90: Color(0xFF666666),
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
      final process = await Process.start(
        'git',
        ['pull'],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      final exitCode = await process.exitCode;
      if (!mounted) return;
      if (exitCode == 0) {
        _addLine('\x1B[0;32m[+] ${context.l10n.gitPullDone}\x1B[0m');
      } else {
        _addLine(
          '\x1B[0;31m[-] ${context.l10n.gitPullFailed(exitCode)}\x1B[0m',
        );
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
        spans.add(
          TextSpan(
            text: line.substring(lastEnd, match.start),
            style: TextStyle(color: currentColor),
          ),
        );
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
      spans.add(
        TextSpan(
          text: line.substring(lastEnd),
          style: TextStyle(color: currentColor),
        ),
      );
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
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
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

// ── Simple Git Commit dialog ──

class _SimpleGitCommitDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const _SimpleGitCommitDialog({
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<_SimpleGitCommitDialog> createState() => _SimpleGitCommitDialogState();
}

class _SimpleGitCommitDialogState extends State<_SimpleGitCommitDialog> {
  static final _ansiRegex = RegExp(r'\x1B\[[0-9;]*m');
  static const _ansiColors = <int, Color>{
    31: Color(0xFFCD3131),
    32: Color(0xFF0DBC79),
    33: Color(0xFFE5E510),
    34: Color(0xFF2472C8),
    90: Color(0xFF666666),
  };

  final List<String> _logLines = [];
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  bool _running = false;
  bool _loading = true;
  bool _pushAfterCommit = true;

  /// Each entry: {'status': 'M', 'file': 'path/to/file', 'selected': true}
  List<Map<String, dynamic>> _changedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadStatus();
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

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final result = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      if (!mounted) return;
      final output = (result.stdout as String).trimRight();
      if (output.isEmpty) {
        // Kiểm tra xem git có lỗi không
        final stderr = (result.stderr as String).trim();
        if (stderr.isNotEmpty) {
          _addLine('\x1B[0;31m[-] $stderr\x1B[0m');
        }
        setState(() {
          _changedFiles = [];
          _loading = false;
        });
        return;
      }
      final files = <Map<String, dynamic>>[];
      for (final line in output.split('\n')) {
        if (line.length < 4) continue;
        // git status --porcelain format: XY filename (XY = 2 chars, then space, then filename)
        final status = line.substring(0, 2).trim();
        var file = line.substring(3);
        if (status.isEmpty || file.isEmpty) continue;
        // Handle renames: "old -> new"
        if (file.contains(' -> ')) file = file.split(' -> ').last;
        files.add({'status': status, 'file': file, 'selected': true});
      }
      setState(() {
        _changedFiles = files;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _addLine('\x1B[0;31m[-] $e\x1B[0m');
      }
    }
  }

  int get _selectedCount =>
      _changedFiles.where((f) => f['selected'] == true).length;

  bool get _canCommit =>
      !_running &&
      !_loading &&
      _selectedCount > 0 &&
      _messageController.text.trim().isNotEmpty;

  Future<void> _commit() async {
    setState(() => _running = true);

    final selectedFiles = _changedFiles
        .where((f) => f['selected'] == true)
        .toList();
    final filePaths = selectedFiles.map((f) => f['file'] as String).toList();
    final message = _messageController.text.trim();

    try {
      // git add files one by one
      _addLine('\x1B[0;34m> git add (${filePaths.length} files)\x1B[0m');
      for (final file in filePaths) {
        final addResult = await Process.run(
          'git',
          ['add', '--', file],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );
        if (addResult.exitCode != 0) {
          _addLine('\x1B[0;31m[-] git add failed for: $file\x1B[0m');
          if ((addResult.stderr as String).trim().isNotEmpty) {
            _addLine((addResult.stderr as String).trim());
          }
          if (mounted) setState(() => _running = false);
          return;
        }
      }

      // git commit -m "message"
      _addLine('\x1B[0;34m> git commit -m "$message"\x1B[0m');
      final commitProcess = await Process.start(
        'git',
        ['commit', '-m', message],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      commitProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      commitProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (mounted) _addLine(line);
          });
      final commitExit = await commitProcess.exitCode;
      if (!mounted) return;

      if (commitExit != 0) {
        _addLine(
          '\x1B[0;31m[-] ${context.l10n.gitCommitFailed(commitExit)}\x1B[0m',
        );
        setState(() => _running = false);
        return;
      }
      _addLine('\x1B[0;32m[+] ${context.l10n.gitCommitDone}\x1B[0m');

      // Optional push
      if (_pushAfterCommit) {
        _addLine('\x1B[0;34m> git push\x1B[0m');
        final pushProcess = await Process.start(
          'git',
          ['push'],
          workingDirectory: widget.projectPath,
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
        if (!mounted) return;
        if (pushExit == 0) {
          _addLine('\x1B[0;32m[+] Push done\x1B[0m');
        } else {
          _addLine('\x1B[0;31m[-] Push failed (exit $pushExit)\x1B[0m');
        }
      }
    } catch (e) {
      if (mounted) _addLine('\x1B[0;31m[-] $e\x1B[0m');
    }
    if (mounted) {
      setState(() => _running = false);
      // Reload status to show remaining changes
      await _loadStatus();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'M':
        return const Color(0xFFE5E510); // yellow
      case 'A':
        return const Color(0xFF0DBC79); // green
      case 'D':
        return const Color(0xFFCD3131); // red
      case '??':
        return Colors.grey;
      case 'R':
        return const Color(0xFF2472C8); // blue
      default:
        return Colors.grey.shade300;
    }
  }

  List<TextSpan> _parseAnsi(String line) {
    final spans = <TextSpan>[];
    final defaultColor = Colors.grey.shade300;
    var currentColor = defaultColor;
    var lastEnd = 0;

    for (final match in _ansiRegex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: line.substring(lastEnd, match.start),
            style: TextStyle(color: currentColor),
          ),
        );
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
      spans.add(
        TextSpan(
          text: line.substring(lastEnd),
          style: TextStyle(color: currentColor),
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _changedFiles.isNotEmpty &&
        _changedFiles.every((f) => f['selected'] == true);

    return AlertDialog(
      title: Text(context.l10n.gitCommitTitle(widget.projectName)),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(),
              )
            else if (_changedFiles.isEmpty && _logLines.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    context.l10n.gitCommitNoChanges,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ] else ...[
              // File list with checkboxes
              if (_changedFiles.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      context.l10n.gitStagedFiles(_selectedCount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _running
                          ? null
                          : () {
                              setState(() {
                                final newVal = !allSelected;
                                for (final f in _changedFiles) {
                                  f['selected'] = newVal;
                                }
                              });
                            },
                      icon: Icon(
                        allSelected ? Icons.deselect : Icons.select_all,
                        size: AppIconSize.md,
                      ),
                      label: Text(
                        allSelected
                            ? context.l10n.gitDeselectAll
                            : context.l10n.gitSelectAll,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade600),
                    borderRadius: AppRadius.mediumBorderRadius,
                  ),
                  child: ListView.builder(
                    itemCount: _changedFiles.length,
                    itemBuilder: (ctx, i) {
                      final f = _changedFiles[i];
                      final status = f['status'] as String;
                      final file = f['file'] as String;
                      final selected = f['selected'] as bool;
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        onChanged: _running
                            ? null
                            : (v) => setState(
                                () => _changedFiles[i]['selected'] = v!,
                              ),
                        title: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$status  ',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: _statusColor(status),
                                  fontSize: AppFontSize.md,
                                ),
                              ),
                              TextSpan(
                                text: file,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.md,
                                ),
                              ),
                            ],
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Commit message
                TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    labelText: context.l10n.gitCommitMessage,
                    hintText: context.l10n.gitCommitMessageHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 8,
                  minLines: 3,
                  enabled: !_running,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Push checkbox + commit button
                Row(
                  children: [
                    GestureDetector(
                      onTap: _running
                          ? null
                          : () => setState(
                              () => _pushAfterCommit = !_pushAfterCommit,
                            ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _pushAfterCommit,
                            onChanged: _running
                                ? null
                                : (v) => setState(
                                    () => _pushAfterCommit = v ?? false,
                                  ),
                          ),
                          Text(context.l10n.gitPushAfterCommit),
                        ],
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _canCommit ? _commit : null,
                      icon: const Icon(Icons.check, size: AppIconSize.md),
                      label: Text(
                        _pushAfterCommit
                            ? context.l10n.gitCommitAndPush
                            : context.l10n.gitCommitOnly,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Log output area
              if (_logLines.isNotEmpty || _running)
                Container(
                  height: 180,
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
                              color: Colors.grey,
                              fontFamily: 'monospace',
                            ),
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

            if (_running)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: LinearProgressIndicator(),
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

// ── Switch Branch Dialog ──

class _SwitchBranchDialog extends StatefulWidget {
  final String projectPath;
  final String currentBranch;
  final Color Function(String) branchColor;
  final void Function(String branch) onSwitched;

  const _SwitchBranchDialog({
    required this.projectPath,
    required this.currentBranch,
    required this.branchColor,
    required this.onSwitched,
  });

  @override
  State<_SwitchBranchDialog> createState() => _SwitchBranchDialogState();
}

class _SwitchBranchDialogState extends State<_SwitchBranchDialog> {
  List<String> _local = [];
  List<String> _remote = [];
  String _current = '';
  bool _loading = true;
  bool _switching = false;
  String? _message;
  bool _isError = false;
  int _changedFiles = 0;
  int _behindRemote = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.currentBranch;
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _loading = true);
    final result = await Process.run(
      'git',
      ['branch', '-a', '--format=%(refname)'],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (result.exitCode != 0 || !mounted) {
      setState(() => _loading = false);
      return;
    }

    final localBranches = <String>{};
    final remoteBranches = <String>{};
    for (final ref
        in (result.stdout as String)
            .split('\n')
            .map((b) => b.trim())
            .where((b) => b.isNotEmpty)) {
      if (ref.contains('HEAD')) continue;
      if (ref.startsWith('refs/heads/')) {
        localBranches.add(ref.substring('refs/heads/'.length));
      } else if (ref.startsWith('refs/remotes/origin/')) {
        remoteBranches.add(ref.substring('refs/remotes/origin/'.length));
      }
    }

    // Load changed files count
    int changed = 0;
    final statusResult = await Process.run(
      'git',
      ['status', '--porcelain'],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (statusResult.exitCode == 0) {
      changed = (statusResult.stdout as String)
          .trimRight()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .length;
    }

    // Load behind remote count
    int behind = 0;
    final behindResult = await Process.run(
      'git',
      ['rev-list', '--count', 'HEAD..@{upstream}'],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (behindResult.exitCode == 0) {
      behind = int.tryParse((behindResult.stdout as String).trim()) ?? 0;
    }

    if (mounted) {
      setState(() {
        _local = localBranches.toList()
          ..sort((a, b) {
            if (a == _current) return -1;
            if (b == _current) return 1;
            return a.compareTo(b);
          });
        _remote = remoteBranches.toList()..sort();
        _changedFiles = changed;
        _behindRemote = behind;
        _loading = false;
      });
    }
  }

  Future<void> _pruneCheck() async {
    setState(() {
      _switching = true;
      _message = null;
    });
    // Fetch + prune remote refs
    await Process.run(
      'git',
      ['fetch', '--prune'],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    // Find local branches whose upstream is gone
    final result = await Process.run(
      'git',
      ['branch', '-vv'],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (!mounted) return;

    final gone = <String>[];
    for (final line in (result.stdout as String).split('\n')) {
      if (line.contains(': gone]')) {
        final branch = line
            .trim()
            .split(RegExp(r'\s+'))
            .first
            .replaceFirst('*', '')
            .trim();
        if (branch.isNotEmpty && branch != _current) {
          gone.add(branch);
        }
      }
    }

    if (gone.isEmpty) {
      setState(() {
        _switching = false;
        _message = 'All local branches are up to date with remote';
        _isError = false;
      });
      return;
    }

    setState(() => _switching = false);

    if (!mounted) return;
    final toDelete = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _PruneDialog(branches: gone),
    );
    if (toDelete == null || toDelete.isEmpty || !mounted) return;

    final deleted = <String>[];
    final failed = <String>[];
    for (final branch in toDelete) {
      final del = await Process.run(
        'git',
        ['branch', '-D', branch],
        workingDirectory: widget.projectPath,
        runInShell: true,
      );
      if (del.exitCode == 0) {
        deleted.add(branch);
      } else {
        failed.add(branch);
      }
    }

    if (mounted) {
      setState(() {
        if (deleted.isNotEmpty) {
          _message = 'Deleted: ${deleted.join(', ')}';
          _isError = false;
        }
        if (failed.isNotEmpty) {
          _message =
              '${_message ?? ''}${_message != null ? '\n' : ''}Failed: ${failed.join(', ')}';
          _isError = failed.isNotEmpty && deleted.isEmpty;
        }
      });
      _loadBranches();
    }
  }

  Future<void> _createBranch() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Branch name',
            hintText: 'feature/my-feature',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;

    final result = await Process.run(
      'git',
      ['checkout', '-b', name],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (!mounted) return;
    if (result.exitCode == 0) {
      setState(() {
        _current = name;
        _message = 'Created and switched to $name';
        _isError = false;
      });
      widget.onSwitched(name);
      _loadBranches();
    } else {
      setState(() {
        _message = (result.stderr as String).trim();
        _isError = true;
      });
    }
  }

  Future<void> _deleteBranch(String branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Branch'),
        content: Text('Delete local branch "$branch"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await Process.run(
      'git',
      ['branch', '-d', branch],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (!mounted) return;
    if (result.exitCode == 0) {
      setState(() {
        _message = 'Deleted branch $branch';
        _isError = false;
      });
      _loadBranches();
    } else {
      // Try force delete if not merged
      final stderr = (result.stderr as String).trim();
      if (stderr.contains('not fully merged')) {
        final force = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Force Delete?'),
            content: Text(
              'Branch "$branch" is not fully merged. Force delete?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Force Delete'),
              ),
            ],
          ),
        );
        if (force == true && mounted) {
          final forceResult = await Process.run(
            'git',
            ['branch', '-D', branch],
            workingDirectory: widget.projectPath,
            runInShell: true,
          );
          if (mounted) {
            if (forceResult.exitCode == 0) {
              setState(() {
                _message = 'Force deleted branch $branch';
                _isError = false;
              });
              _loadBranches();
            } else {
              setState(() {
                _message = (forceResult.stderr as String).trim();
                _isError = true;
              });
            }
          }
        }
      } else {
        setState(() {
          _message = stderr;
          _isError = true;
        });
      }
    }
  }

  Future<void> _mergeBranch(String branch) async {
    // branch = target branch (not current)
    // Ask merge direction
    final direction = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Option 1: merge target INTO current
            ListTile(
              leading: const Icon(Icons.arrow_back, color: Colors.blue),
              title: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Merge '),
                    TextSpan(
                      text: branch,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const TextSpan(text: ' into '),
                    TextSpan(
                      text: _current,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              subtitle: Text('Cập nhật $_current với code từ $branch'),
              onTap: () => Navigator.pop(ctx, 'into_current'),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mediumBorderRadius,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Option 2: merge current INTO target
            ListTile(
              leading: const Icon(Icons.arrow_forward, color: Colors.green),
              title: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Merge '),
                    TextSpan(
                      text: _current,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const TextSpan(text: ' into '),
                    TextSpan(
                      text: branch,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              subtitle: Text('Đẩy code $_current sang $branch'),
              onTap: () => Navigator.pop(ctx, 'into_target'),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mediumBorderRadius,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
    if (direction == null || !mounted) return;

    setState(() {
      _switching = true;
      _message = null;
    });

    try {
      if (direction == 'into_current') {
        // git merge <branch> (merge target into current)
        final result = await Process.run(
          'git',
          ['merge', branch],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );
        if (!mounted) return;
        if (result.exitCode == 0) {
          // Push current branch
          final push = await Process.run(
            'git',
            ['push'],
            workingDirectory: widget.projectPath,
            runInShell: true,
          );
          setState(() {
            _switching = false;
            _message = push.exitCode == 0
                ? 'Merged $branch into $_current and pushed'
                : 'Merged $branch into $_current (push failed: ${(push.stderr as String).trim()})';
            _isError = push.exitCode != 0;
          });
        } else {
          setState(() {
            _switching = false;
            _message = (result.stderr as String).trim().isNotEmpty
                ? (result.stderr as String).trim()
                : (result.stdout as String).trim();
            _isError = true;
          });
        }
      } else {
        // direction == 'into_target'
        // git checkout <target> → git merge <current> → git push → git checkout <current>
        final savedCurrent = _current;

        // Checkout target
        var result = await Process.run(
          'git',
          ['checkout', branch],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );
        if (result.exitCode != 0) {
          if (mounted) {
            setState(() {
              _switching = false;
              _message =
                  'Checkout $branch failed: ${(result.stderr as String).trim()}';
              _isError = true;
            });
          }
          return;
        }

        // Merge current into target
        result = await Process.run(
          'git',
          ['merge', savedCurrent],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );
        if (result.exitCode != 0) {
          // Merge failed — stay on target branch so user can resolve
          if (mounted) {
            setState(() {
              _current = branch;
              _switching = false;
              _message =
                  'Merge failed: ${(result.stderr as String).trim().isNotEmpty ? (result.stderr as String).trim() : (result.stdout as String).trim()}';
              _isError = true;
            });
          }
          widget.onSwitched(branch);
          _loadBranches();
          return;
        }

        // Push target
        final push = await Process.run(
          'git',
          ['push'],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );

        // Checkout back to original branch
        await Process.run(
          'git',
          ['checkout', savedCurrent],
          workingDirectory: widget.projectPath,
          runInShell: true,
        );

        if (mounted) {
          setState(() {
            _current = savedCurrent;
            _switching = false;
            _message = push.exitCode == 0
                ? 'Merged $savedCurrent into $branch and pushed'
                : 'Merged $savedCurrent into $branch (push failed: ${(push.stderr as String).trim()})';
            _isError = push.exitCode != 0;
          });
          widget.onSwitched(savedCurrent);
          _loadBranches();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _switching = false;
          _message = e.toString();
          _isError = true;
        });
      }
    }
  }

  Future<void> _checkout(String branch) async {
    setState(() {
      _switching = true;
      _message = null;
    });
    final result = await Process.run(
      'git',
      ['checkout', branch],
      workingDirectory: widget.projectPath,
      runInShell: true,
    );
    if (!mounted) return;
    if (result.exitCode == 0) {
      setState(() {
        _current = branch;
        _switching = false;
        _message = 'Switched to $branch';
        _isError = false;
      });
      widget.onSwitched(branch);
      _loadBranches();
    } else {
      setState(() {
        _switching = false;
        _message = (result.stderr as String).trim();
        _isError = true;
      });
    }
  }

  Widget _buildLocalColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_tree,
              size: AppIconSize.md,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Local',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._local.map((b) => _branchTile(b)),
      ],
    );
  }

  Widget _buildRemoteColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.cloud_outlined,
              size: AppIconSize.md,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Remote',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._remote.map((b) => _branchTile(b, isRemote: true)),
      ],
    );
  }

  Widget _branchTile(String branch, {bool isRemote = false}) {
    final isCurrent = !isRemote && branch == _current;
    final canTap = !isCurrent && !_switching;
    return InkWell(
        onTap: canTap ? () => _checkout(branch) : null,
        mouseCursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: AppRadius.smallBorderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.check_circle : Icons.circle_outlined,
              size: AppIconSize.lg,
              color: isCurrent ? widget.branchColor(branch) : Colors.grey,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                branch,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.xl,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                  color: isCurrent ? widget.branchColor(branch) : null,
                ),
              ),
            ),
            if (isRemote)
              Icon(
                Icons.cloud_outlined,
                size: AppIconSize.md,
                color: Colors.grey.shade500,
              ),
            if (!isRemote && !isCurrent) ...[
              IconButton(
                onPressed: _switching ? null : () => _mergeBranch(branch),
                icon: const Icon(
                  Icons.merge,
                  size: AppIconSize.md,
                  color: Colors.blue,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppIconSize.xl,
                  minHeight: AppIconSize.xl,
                ),
                tooltip: 'Merge',
              ),
              if (branch != 'main' && branch != 'master')
                IconButton(
                  onPressed: _switching ? null : () => _deleteBranch(branch),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: AppIconSize.md,
                    color: Colors.red,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppIconSize.xl,
                    minHeight: 24,
                  ),
                  tooltip: 'Delete branch',
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('Git Branches'),
          if (_current.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Chip(
              avatar: Icon(
                Icons.check_circle,
                size: AppIconSize.md,
                color: widget.branchColor(_current),
              ),
              label: Text(
                _current,
                style: TextStyle(
                  color: widget.branchColor(_current),
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.md,
                ),
              ),
              backgroundColor:
                  widget.branchColor(_current).withValues(alpha: 0.1),
              visualDensity: VisualDensity.compact,
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          TextButton.icon(
            onPressed: _switching ? null : _pruneCheck,
            icon: const Icon(Icons.cleaning_services, size: AppIconSize.md),
            label: const Text('Clean stale'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
        ],
      ),
      content: Builder(
        builder: (context) {
          final isWide = MediaQuery.of(context).size.width > 900;
          return SizedBox(
            width: isWide ? AppDialog.widthLg : AppDialog.widthMd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Action bar
                Row(
                  children: [
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: _switching
                          ? null
                          : () async {
                              await showDialog(
                                context: context,
                                builder: (ctx) => _SimpleGitPullDialog(
                                  projectName: p.basename(widget.projectPath),
                                  projectPath: widget.projectPath,
                                ),
                              );
                              if (mounted) {
                                setState(() => _message = null);
                                _loadBranches();
                              }
                            },
                      icon: const Icon(Icons.download, size: AppIconSize.md),
                      label: const Text('Pull'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: _switching
                          ? null
                          : () async {
                              await showDialog(
                                context: context,
                                builder: (ctx) => _SimpleGitCommitDialog(
                                  projectName: p.basename(widget.projectPath),
                                  projectPath: widget.projectPath,
                                ),
                              );
                              if (mounted) {
                                setState(() => _message = null);
                                _loadBranches();
                              }
                            },
                      icon: const Icon(Icons.commit, size: AppIconSize.md),
                      label: const Text('Commit'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _switching ? null : _createBranch,
                      icon: const Icon(Icons.add, size: AppIconSize.md),
                      label: const Text('Create'),
                    ),
                  ],
                ),
                // Status info
                if (!_loading && (_changedFiles > 0 || _behindRemote > 0)) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (_changedFiles > 0)
                        Chip(
                          avatar: const Icon(
                            Icons.edit_note,
                            size: AppIconSize.md,
                            color: Colors.orange,
                          ),
                          label: Text(
                            '$_changedFiles changed',
                            style: const TextStyle(color: Colors.orange),
                          ),
                          backgroundColor: Colors.orange.withValues(alpha: 0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (_changedFiles > 0 && _behindRemote > 0)
                        const SizedBox(width: AppSpacing.sm),
                      if (_behindRemote > 0)
                        Chip(
                          avatar: const Icon(
                            Icons.arrow_downward,
                            size: AppIconSize.md,
                            color: Colors.cyan,
                          ),
                          label: Text(
                            '$_behindRemote behind',
                            style: const TextStyle(color: Colors.cyan),
                          ),
                          backgroundColor: Colors.cyan.withValues(alpha: 0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_switching)
                  const Center(child: CircularProgressIndicator())
                else if (isWide)
                  // Wide: 2 columns
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildLocalColumn()),
                        if (_remote.isNotEmpty) ...[
                          const VerticalDivider(width: AppSpacing.xxl),
                          Expanded(child: _buildRemoteColumn()),
                        ],
                      ],
                    ),
                  )
                else
                  // Narrow: stacked
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLocalColumn(),
                      if (_remote.isNotEmpty) ...[
                        const Divider(height: AppSpacing.xxl),
                        _buildRemoteColumn(),
                      ],
                    ],
                  ),
                if (_message != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: (_isError ? Colors.red : Colors.green).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: AppRadius.smallBorderRadius,
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _isError ? Colors.red : Colors.green,
                        fontFamily: 'monospace',
                        fontSize: AppFontSize.md,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

// ── Prune Stale Branches Dialog ──

class _PruneDialog extends StatefulWidget {
  final List<String> branches;
  const _PruneDialog({required this.branches});

  @override
  State<_PruneDialog> createState() => _PruneDialogState();
}

class _PruneDialogState extends State<_PruneDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.branches.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stale Branches'),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These local branches no longer exist on remote:',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: AppFontSize.md,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...widget.branches.map(
              (b) => CheckboxListTile(
                value: _selected.contains(b),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(b);
                    } else {
                      _selected.remove(b);
                    }
                  });
                },
                title: Text(b, style: const TextStyle(fontFamily: 'monospace')),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        if (_selected.isNotEmpty)
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected.toList()),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete ${_selected.length} branch(es)'),
          ),
      ],
    );
  }
}
