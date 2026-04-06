import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/workspace_info.dart';
import '../../services/platform_service.dart';

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

class ImportWorkspaceDialog extends StatefulWidget {
  final WorkspaceInfo? existing;

  const ImportWorkspaceDialog({super.key, this.existing});

  @override
  State<ImportWorkspaceDialog> createState() => _ImportWorkspaceDialogState();
}

class _ImportWorkspaceDialogState extends State<ImportWorkspaceDialog> {
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
      title: Row(
        children: [
          Text(
            widget.existing != null ? context.l10n.wsEdit : context.l10n.wsImport,
          ),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
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
