import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/workspace_info.dart';
import '../l10n/l10n_extension.dart';
import '../services/platform_service.dart';
import '../services/nginx_service.dart';
import '../services/storage_service.dart';
import '../widgets/nginx_setup_dialog.dart';
import '../widgets/vscode_install_dialog.dart';
import 'home_screen.dart';
import 'projects_screen.dart';

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
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    _filtered = _workspaces.where((w) {
      final matchSearch = q.isEmpty ||
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
      await StorageService.removeWorkspace(workspace.path);
      await StorageService.addWorkspace(result.toJson());
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
    showDialog(
      context: context,
      builder: (ctx) => const VscodeInstallDialog(),
    );
  }

  Future<void> _linkNginx(WorkspaceInfo ws) async {
    final nginx = await NginxService.loadSettings();
    final confDir = (nginx['confDir'] ?? '').toString();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (confDir.isEmpty || suffix.isEmpty) {
      HomeScreen.navigateToSettings(settingsTab: 5);
      return;
    }

    final existingSubs = await NginxService.getExistingSubdomains(confDir);
    if (existingSubs.isEmpty) return;

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
              subtitle: Text('$sub$suffix'),
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
        SnackBar(content: Text(context.l10n.nginxLinked('$selected$suffix'))),
      );
    }
    await _load();
  }

  Future<void> _setupNginx(WorkspaceInfo ws) async {
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (suffix.isEmpty || (nginx['confDir'] ?? '').toString().isEmpty) {
      HomeScreen.navigateToSettings(settingsTab: 5);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxNoPort)),
        );
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
      final sub = ws.nginxSubdomain ?? subdomain;
      await NginxService.removeNginx(sub);
      // Clear subdomain from workspace
      final updated = ws.copyWith(nginxSubdomain: () => null);
      await StorageService.removeWorkspace(ws.path);
      await StorageService.addWorkspace(updated.toJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.l10n.nginxRemoveSuccess('$sub$suffix'))),
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
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(context.l10n.delete)),
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
                        avatar: Icon(_iconForType(ws.type),
                            size: AppIconSize.md,
                            color: _colorForType(ws.type)),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (ws.description.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Chip(
                          label: Text(ws.description,
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
                      tooltip: ws.favourite ? context.l10n.unfavourite : context.l10n.favourite,
                    ),
                    if (exists) ...[
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
        final cellWidth = (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
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
                      // Favourite star top-right
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          onPressed: () => _toggleFavourite(ws),
                          icon: Icon(
                            ws.favourite ? Icons.star : Icons.star_border,
                            size: AppIconSize.lg,
                            color: ws.favourite ? Colors.amber : Colors.grey.shade600,
                          ),
                          tooltip: ws.favourite ? context.l10n.unfavourite : context.l10n.favourite,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                      const Spacer(),
                      // Project type as accent badge
                      if (ws.type.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs),
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
                      // Quick action buttons (VSCode + folder only)
                      if (exists)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: AppSpacing.lg,
                          children: [
                            _gridBtn(
                              icon: Icons.code,
                              tooltip: context.l10n.openInVscode,
                              onPressed: () => _openInVscode(ws.path),
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
      Offset position, WorkspaceInfo ws, bool exists) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'favourite',
          child: Row(
            children: [
              Icon(ws.favourite ? Icons.star : Icons.star_border,
                  size: AppIconSize.md,
                  color: ws.favourite ? Colors.amber : null),
              const SizedBox(width: AppSpacing.sm),
              Text(ws.favourite ? context.l10n.unfavourite : context.l10n.favourite),
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
      case 'favourite':
        _toggleFavourite(ws);
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
              Text(context.l10n.wsTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                onPressed: () {
                  setState(() => ProjectsScreen.gridView = !ProjectsScreen.gridView);
                  ProjectsScreen.saveViewPreference();
                },
                icon: Icon(ProjectsScreen.gridView ? Icons.view_list : Icons.grid_view),
                tooltip: ProjectsScreen.gridView ? context.l10n.wsViewList : context.l10n.wsViewGrid,
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
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
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
                    ..._allTypes.map((t) => PopupMenuItem(
                          value: t.toLowerCase(),
                          child: Row(
                            children: [
                              Icon(_iconForType(t),
                                  size: AppIconSize.md,
                                  color: _colorForType(t)),
                              const SizedBox(width: AppSpacing.sm),
                              Text(t),
                            ],
                          ),
                        )),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_workspaces.isEmpty)
            Expanded(
              child: Center(child: Text(context.l10n.wsEmpty)),
            )
          else if (_filtered.isEmpty)
            Expanded(
              child: Center(child: Text(context.l10n.wsNoMatch)),
            )
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
        text: e?.port != null ? '${e!.port}' : '');
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
      title: Text(widget.existing != null
          ? context.l10n.wsEdit
          : context.l10n.wsImport),
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
            child: Text(context.l10n.cancel)),
        FilledButton(
          onPressed:
              (_workspacePath.isNotEmpty && _nameController.text.isNotEmpty)
                  ? _save
                  : null,
          child: Text(
              widget.existing != null ? context.l10n.save : context.l10n.import_),
        ),
      ],
    );
  }
}
