import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/workspace_info.dart';
import '../l10n/l10n_extension.dart';
import '../services/platform_service.dart';
import '../services/storage_service.dart';

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
    setState(() {
      _workspaces = json.map((j) => WorkspaceInfo.fromJson(j)).toList();
      _workspaces.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              const Icon(Icons.workspaces, size: AppIconSize.xl),
              Text(context.l10n.wsTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: AppSpacing.xxxl),
              FilledButton.icon(
                onPressed: _importWorkspace,
                icon: const Icon(Icons.add),
                label: Text(context.l10n.import_),
              ),
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
              child: ListView.builder(
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
                                exists
                                    ? _iconForType(ws.type)
                                    : Icons.folder_off,
                                color: exists
                                    ? _colorForType(ws.type)
                                    : Colors.grey,
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
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: AppSpacing.xs,
                            children: [
                              if (exists) ...[
                                IconButton(
                                  onPressed: () => _openInVscode(ws.path),
                                  icon: const Icon(Icons.code),
                                  tooltip: context.l10n.openInVscode,
                                ),
                                IconButton(
                                  onPressed: () =>
                                      _openInFileManager(ws.path),
                                  icon: const Icon(Icons.folder_open),
                                  tooltip: context.l10n.openFolder,
                                ),
                              ],
                              IconButton(
                                onPressed: () => _editWorkspace(ws),
                                icon: const Icon(Icons.edit),
                                tooltip: context.l10n.edit,
                              ),
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
              ),
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
  late String _workspacePath;
  late String _description;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _typeController = TextEditingController(text: e?.type ?? '');
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

    final workspace = WorkspaceInfo(
      name: _nameController.text.trim(),
      path: _workspacePath,
      type: _typeController.text.trim(),
      description: _description,
      createdAt: widget.existing?.createdAt ?? DateTime.now().toIso8601String(),
    );

    Navigator.pop(context, workspace);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
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
