import 'dart:io';
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
      _loading = false;
    });
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
              IconButton.filled(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'All created projects with quick access.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_projects.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No projects yet. Use Quick Create to start.'),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _projects.length,
                itemBuilder: (context, index) {
                  final proj = _projects[index];
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
                              Chip(
                                  label: Text(proj.profileName),
                                  avatar:
                                      const Icon(Icons.person, size: 16)),
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
