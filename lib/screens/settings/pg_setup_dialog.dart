import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/postgres_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class PgSetupDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const PgSetupDialog({super.key, required this.onCreated});

  @override
  State<PgSetupDialog> createState() => _PgSetupDialogState();
}

class _PgSetupDialogState extends State<PgSetupDialog> {
  final _userController =
      TextEditingController(text: PostgresService.defaultUser);
  final _passwordController = TextEditingController();
  final _portController =
      TextEditingController(text: PostgresService.defaultPort.toString());

  String _baseDir = '';
  bool _creating = false;
  bool _created = false;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _passwordController.text = PostgresService.defaultPassword;
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _pickBaseDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.postgresSetupBaseDir);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.postgresSetupBaseDir);
    }
    if (path != null) setState(() => _baseDir = path!);
  }

  bool get _isValid =>
      _baseDir.isNotEmpty &&
      _userController.text.trim().isNotEmpty &&
      _passwordController.text.trim().isNotEmpty &&
      _portController.text.trim().isNotEmpty;

  Future<void> _create() async {
    if (!_isValid) return;
    setState(() {
      _creating = true;
      _logLines.clear();
    });
    context.setDialogRunning(true);

    try {
      final projectDir = await PostgresService.initProject(
        baseDir: _baseDir,
        dbUser: _userController.text.trim(),
        dbPassword: _passwordController.text.trim(),
        hostPort: int.tryParse(_portController.text.trim()) ??
            PostgresService.defaultPort,
        onOutput: (line) {
          if (mounted) setState(() => _logLines.add(line));
        },
      );

      if (mounted) {
        setState(() {
          _creating = false;
          _created = true;
        });
        context.setDialogRunning(false);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n.postgresSetupSuccess(projectDir))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _logLines.add('[ERROR] $e');
        });
        context.setDialogRunning(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Text(context.l10n.postgresSetupTitle),
        const Spacer(),
        AppDialog.closeButton(context),
      ]),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: AppDialog.contentMaxHeight(context),
            ),
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.postgresSetupSubtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: AppSpacing.lg),
              // Base directory
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _baseDir),
                      decoration: InputDecoration(
                        labelText: context.l10n.postgresSetupBaseDir,
                        hintText: context.l10n.browseToSelect,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _pickBaseDir,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // User + Password
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userController,
                      decoration: InputDecoration(
                        labelText: context.l10n.postgresSetupUser,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: context.l10n.postgresSetupPassword,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Port
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: context.l10n.postgresSetupPort,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
              ],
            ],
          ),
        ),
        ),
      ),
      actions: [
        if (!_created)
          FilledButton.icon(
            onPressed: (_creating || !_isValid) ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.rocket_launch),
            label: Text(_creating
                ? context.l10n.creating
                : context.l10n.postgresSetupDocker),
          ),
        if (_created)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text(context.l10n.close),
          ),
      ],
    );
  }
}
