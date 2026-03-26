import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/project_info.dart';
import '../services/storage_service.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

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
    setState(() {
      _projects = json.map((j) => ProjectInfo.fromJson(j)).toList();
      _projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  Future<void> _importProject() async {
    final result = await showDialog<ProjectInfo>(
      context: context,
      builder: (ctx) => const _ImportProjectDialog(),
    );
    if (result != null) {
      // Check port conflict
      final conflict = await StorageService.checkPortConflict(
          result.httpPort, result.longpollingPort, result.path);
      if (conflict != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(conflict),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await StorageService.addProject(result.toJson());
      await _load();
    }
  }

  Future<void> _openInFileManager(String path) async {
    try {
      await Process.run('xdg-open', [path]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $path')),
        );
      }
    }
  }

  Future<void> _openInVscode(String path) async {
    try {
      await Process.run('code', [path]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open VSCode')),
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
      // Remove old entry (path might have changed) then add new
      await StorageService.removeProject(project.path);
      await StorageService.addProject(result.toJson());
      await _load();
    }
  }

  Future<void> _remove(ProjectInfo project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove project?'),
        content: Text(
            'Remove "${project.name}" from the list?\nThis does NOT delete project files.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.removeProject(project.path);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_special, size: 28),
              const SizedBox(width: 12),
              Text('Projects',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: _importProject,
                icon: const Icon(Icons.add),
                label: const Text('Import'),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'All projects with quick access. Import existing or create new ones.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name, path, label, port...',
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
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_projects.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                    'No projects yet. Use Quick Create or Import to add.'),
              ),
            )
          else if (_filtered.isEmpty)
            const Expanded(
              child: Center(child: Text('No projects match your search.')),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final proj = _filtered[index];
                  final exists = Directory(proj.path).existsSync();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                exists
                                    ? Icons.folder_special
                                    : Icons.folder_off,
                                color:
                                    exists ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  proj.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (proj.description.isNotEmpty)
                                Flexible(
                                  child: Chip(
                                    label: Text(proj.description,
                                        overflow: TextOverflow.ellipsis),
                                    avatar: const Icon(Icons.description,
                                        size: 16),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            proj.path,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Chip(
                                avatar:
                                    const Icon(Icons.lan, size: 14),
                                label: Text(
                                    'HTTP: ${proj.httpPort}'),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                avatar:
                                    const Icon(Icons.sync, size: 14),
                                label: Text(
                                    'LP: ${proj.longpollingPort}'),
                              ),
                              const Spacer(),
                              if (exists) ...[
                                IconButton(
                                  onPressed: () =>
                                      _openInVscode(proj.path),
                                  icon: const Icon(Icons.code),
                                  tooltip: 'Open in VSCode',
                                ),
                                IconButton(
                                  onPressed: () =>
                                      _openInFileManager(proj.path),
                                  icon: const Icon(Icons.folder_open),
                                  tooltip: 'Open folder',
                                ),
                              ],
                              IconButton(
                                onPressed: () => _editProject(proj),
                                icon: const Icon(Icons.edit),
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                onPressed: () => _remove(proj),
                                icon: const Icon(Icons.delete),
                                color: Colors.red,
                                tooltip: 'Remove from list',
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
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select existing Odoo project directory',
    );
    if (path == null) return;

    setState(() {
      _projectPath = path;
      _nameController.text = path.split('/').last.split('\\').last;
    });

    // Try auto-detect ports from odoo.conf
    await _autoDetectFromConf(path);
  }

  Future<void> _autoDetectFromConf(String projectPath) async {
    final confPaths = [
      '$projectPath/odoo.conf',
      '$projectPath/config/odoo.conf',
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
      title: Text(widget.existing != null ? 'Edit Project' : 'Import Existing Project'),
      content: SizedBox(
        width: 500,
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
                      decoration: const InputDecoration(
                        labelText: 'Project Directory',
                        hintText: 'Browse to select...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _pickDir,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),

              if (_autoDetected) ...[
                const SizedBox(height: 8),
                Card(
                  color: Colors.green.withValues(alpha: 0.1),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high,
                            color: Colors.green, size: 16),
                        SizedBox(width: 8),
                        Text('Ports auto-detected from odoo.conf'),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Project name
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Project Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // Profile label (optional)
              TextField(
                controller: TextEditingController(text: _description),
                onChanged: (v) => _description = v,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'e.g. Polish tax project for client X',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // Ports
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _httpPortController,
                      decoration: const InputDecoration(
                        labelText: 'HTTP Port',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _lpPortController,
                      decoration: const InputDecoration(
                        labelText: 'Longpolling Port',
                        border: OutlineInputBorder(),
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
            child: const Text('Cancel')),
        FilledButton(
          onPressed: (_projectPath.isNotEmpty &&
                  _nameController.text.isNotEmpty)
              ? _save
              : null,
          child: Text(widget.existing != null ? 'Save' : 'Import'),
        ),
      ],
    );
  }
}
