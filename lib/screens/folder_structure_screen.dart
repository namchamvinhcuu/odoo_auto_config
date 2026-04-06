import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/models/folder_structure_config.dart';
import 'package:odoo_auto_config/services/folder_structure_service.dart';
import 'package:odoo_auto_config/widgets/directory_picker_field.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

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
    } on SymlinkPermissionException catch (e) {
      if (mounted) {
        setState(() {
          _logs.add('[ERROR] $e');
          _generating = false;
        });
        AppDialog.show(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: AppIconSize.lg),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.symlinkErrorTitle),
                const Spacer(),
                AppDialog.closeButton(ctx),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.symlinkErrorDesc),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  color: Colors.orange.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.symlinkErrorSteps,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.sm),
                        Text(context.l10n.symlinkErrorStep1),
                        Text(context.l10n.symlinkErrorStep2),
                        Text(context.l10n.symlinkErrorStep3),
                        Text(context.l10n.symlinkErrorStep4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
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
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.create_new_folder, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(
                context.l10n.folderStructureTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.folderStructureSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Base directory
          DirectoryPickerField(
            label: context.l10n.baseDirectory,
            value: _baseDir,
            onChanged: (v) => setState(() => _baseDir = v),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Project name & Odoo version row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _projectNameController,
                  decoration: InputDecoration(
                    labelText: context.l10n.projectName,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _odooVersion,
                  decoration: InputDecoration(
                    labelText: context.l10n.odooVersion,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _odooVersions
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(context.l10n.odooVersionLabel(v.toString())),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _odooVersion = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Options
          Wrap(
            spacing: AppSpacing.lg,
            children: [
              _buildCheckbox(context.l10n.addons, _createAddons,
                  (v) => setState(() => _createAddons = v!)),
              _buildCheckbox(context.l10n.thirdPartyAddons, _createThirdPartyAddons,
                  (v) => setState(() => _createThirdPartyAddons = v!)),
              _buildCheckbox(context.l10n.config, _createConfigDir,
                  (v) => setState(() => _createConfigDir = v!)),
              _buildCheckbox(context.l10n.venv, _createVenvDir,
                  (v) => setState(() => _createVenvDir = v!)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Generate button
          FilledButton.icon(
            onPressed:
                (_generating || _baseDir.isEmpty) ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.build_circle),
            label:
                Text(_generating ? context.l10n.generating : context.l10n.generateStructure),
          ),
          const SizedBox(height: AppSpacing.xl),

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
