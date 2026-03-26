import 'package:flutter/material.dart';
import '../models/folder_structure_config.dart';
import '../services/folder_structure_service.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';

class FolderStructureScreen extends StatefulWidget {
  const FolderStructureScreen({super.key});

  @override
  State<FolderStructureScreen> createState() => _FolderStructureScreenState();
}

class _FolderStructureScreenState extends State<FolderStructureScreen> {
  final _service = FolderStructureService();
  final _projectNameController = TextEditingController(text: 'my_odoo_project');
  final _logs = <String>[];

  String _baseDir = '';
  int _odooVersion = 17;
  bool _createAddons = true;
  bool _createThirdPartyAddons = true;
  bool _createConfigDir = true;
  bool _createVenvDir = true;
  bool _generating = false;

  final _odooVersions = [14, 15, 16, 17, 18];

  Future<void> _generate() async {
    if (_baseDir.isEmpty || _projectNameController.text.isEmpty) return;

    setState(() {
      _generating = true;
      _logs.clear();
      _logs.add('[+] Generating Odoo project structure...');
    });

    final config = FolderStructureConfig(
      baseDirectory: _baseDir,
      projectName: _projectNameController.text,
      odooVersion: _odooVersion,
      createAddons: _createAddons,
      createThirdPartyAddons: _createThirdPartyAddons,
      createConfigDir: _createConfigDir,
      createVenvDir: _createVenvDir,
    );

    try {
      final logs = await _service.generate(config);
      setState(() {
        _logs.addAll(logs);
        _logs.add('');
        _logs.add('[+] Project structure generated successfully!');
        _logs.add('[+] Project path: ${config.projectPath}');
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _logs.add('[ERROR] $e');
        _generating = false;
      });
    }
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    super.dispose();
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
              const Icon(Icons.create_new_folder, size: 28),
              const SizedBox(width: 12),
              Text(
                'Generate Folder Structure',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Create a standard Odoo development project structure.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 24),

          // Base directory
          DirectoryPickerField(
            label: 'Base Directory',
            value: _baseDir,
            onChanged: (v) => setState(() => _baseDir = v),
          ),
          const SizedBox(height: 16),

          // Project name & Odoo version row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _projectNameController,
                  decoration: const InputDecoration(
                    labelText: 'Project Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _odooVersion,
                  decoration: const InputDecoration(
                    labelText: 'Odoo Version',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _odooVersions
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text('Odoo $v'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _odooVersion = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Options
          Wrap(
            spacing: 16,
            children: [
              _buildCheckbox('addons', _createAddons,
                  (v) => setState(() => _createAddons = v!)),
              _buildCheckbox('third_party_addons', _createThirdPartyAddons,
                  (v) => setState(() => _createThirdPartyAddons = v!)),
              _buildCheckbox('config', _createConfigDir,
                  (v) => setState(() => _createConfigDir = v!)),
              _buildCheckbox('venv', _createVenvDir,
                  (v) => setState(() => _createVenvDir = v!)),
            ],
          ),
          const SizedBox(height: 20),

          // Generate button
          FilledButton.icon(
            onPressed:
                (_generating || _baseDir.isEmpty) ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.build_circle),
            label:
                Text(_generating ? 'Generating...' : 'Generate Structure'),
          ),
          const SizedBox(height: 20),

          // Output
          Expanded(child: LogOutput(lines: _logs)),
        ],
      ),
    );
  }

  Widget _buildCheckbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Text(label),
      ],
    );
  }
}
