import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

class ImportProjectDialog extends StatefulWidget {
  const ImportProjectDialog({super.key});

  @override
  State<ImportProjectDialog> createState() => _ImportProjectDialogState();
}

class _ImportProjectDialogState extends State<ImportProjectDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _httpPortController;
  late final TextEditingController _lpPortController;
  late String _projectPath;
  late String _description;
  bool _autoDetected = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _httpPortController = TextEditingController(text: '0');
    _lpPortController = TextEditingController(text: '0');
    _projectPath = '';
    _description = '';
    _suggestPorts();
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
      createdAt: DateTime.now().toIso8601String(),
    );

    if (mounted) Navigator.pop(context, project);
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
      title: Row(
        children: [
          Text(context.l10n.importExistingProject),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
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

            ],
          ),
        ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: (_projectPath.isNotEmpty &&
                  _nameController.text.isNotEmpty)
              ? _save
              : null,
          child: Text(context.l10n.import_),
        ),
      ],
    );
  }
}
