import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/venv_info.dart';
import '../services/storage_service.dart';
import '../services/vscode_config_service.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';

class VscodeConfigScreen extends StatefulWidget {
  const VscodeConfigScreen({super.key});

  @override
  State<VscodeConfigScreen> createState() => _VscodeConfigScreenState();
}

class _VscodeConfigScreenState extends State<VscodeConfigScreen> {
  final _service = VscodeConfigService();
  final _nameController = TextEditingController(text: 'Debug Odoo');
  final _logs = <String>[];

  List<VenvInfo> _registeredVenvs = [];
  VenvInfo? _selectedVenv;
  String _projectDir = '';
  String _odooBinPath = '';
  bool _loading = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _loadVenvs();
  }

  Future<void> _loadVenvs() async {
    setState(() => _loading = true);
    final saved = await StorageService.loadRegisteredVenvs();
    setState(() {
      _registeredVenvs = saved.map((j) => VenvInfo.fromJson(j)).toList();
      if (_registeredVenvs.isNotEmpty) _selectedVenv = _registeredVenvs.first;
      _loading = false;
    });
  }

  Future<void> _pickOdooBin() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select odoo-bin',
      type: FileType.any,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _odooBinPath = result.files.single.path!);
    }
  }

  Future<void> _generate() async {
    if (_projectDir.isEmpty ||
        _selectedVenv == null ||
        _odooBinPath.isEmpty) {
      return;
    }

    setState(() {
      _generating = true;
      _logs.clear();
      _logs.add('[+] Generating launch.json...');
    });

    try {
      final logs = await _service.generate(
        projectPath: _projectDir,
        configName: _nameController.text,
        venvPath: _selectedVenv!.path,
        odooBinPath: _odooBinPath,
      );
      setState(() {
        _logs.addAll(logs);
        _logs.add('');
        _logs.add('[+] Done! Select "${_nameController.text}" in VSCode debug panel.');
      });
    } catch (e) {
      setState(() => _logs.add('[ERROR] $e'));
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: AppSpacing.screenPadding,
      child: ListView(
        children: [
          Row(
            children: [
              const Icon(Icons.code, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(
                'VSCode Configuration',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Generate .vscode/launch.json for Odoo debug.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Config name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Configuration Name',
              hintText: 'e.g. Debug Polish Tax Odoo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Project directory
          DirectoryPickerField(
            label: 'Project Directory (where .vscode/ will be created)',
            value: _projectDir,
            onChanged: (v) => setState(() => _projectDir = v),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Venv selector
          DropdownButtonFormField<VenvInfo>(
            initialValue: _selectedVenv,
            decoration: const InputDecoration(
              labelText: 'Virtual Environment',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _registeredVenvs
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(
                        '${v.name}  (${v.path})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedVenv = v),
            hint: const Text('No registered venvs'),
          ),
          const SizedBox(height: AppSpacing.lg),

          // odoo-bin path
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: _odooBinPath),
                  decoration: const InputDecoration(
                    labelText: 'odoo-bin Path',
                    hintText: '/path/to/odoo/odoo-bin',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  readOnly: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: _pickOdooBin,
                icon: const Icon(Icons.file_open),
                tooltip: 'Browse...',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Preview
          if (_selectedVenv != null && _odooBinPath.isNotEmpty)
            _buildPreview(),

          const SizedBox(height: AppSpacing.lg),

          // Generate button
          FilledButton.icon(
            onPressed: (_generating ||
                    _projectDir.isEmpty ||
                    _selectedVenv == null ||
                    _odooBinPath.isEmpty)
                ? null
                : _generate,
            icon: _generating
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.build_circle),
            label: Text(
                _generating ? 'Generating...' : 'Generate launch.json'),
          ),
          const SizedBox(height: AppSpacing.lg),

          LogOutput(lines: _logs),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final preview = const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': '0.2.0',
      'configurations': [
        {
          'name': _nameController.text,
          'type': 'debugpy',
          'request': 'launch',
          'python': '${_selectedVenv!.path}/bin/python',
          'program': _odooBinPath,
          'args': ['-c', '\${workspaceFolder}/odoo.conf', '--dev', 'xml'],
          'env': <String, dynamic>{},
          'console': 'integratedTerminal',
          'justMyCode': false,
        }
      ],
    });

    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppLogColors.terminalBg,
                borderRadius: AppRadius.mediumBorderRadius,
              ),
              child: SelectableText(
                preview,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.sm,
                  color: AppLogColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
