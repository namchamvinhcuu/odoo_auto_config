import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';
import 'package:odoo_auto_config/widgets/status_card.dart';

class NginxInitDialog extends StatefulWidget {
  final void Function(String confDir, String domain) onCreated;
  const NginxInitDialog({super.key, required this.onCreated});

  @override
  State<NginxInitDialog> createState() => _NginxInitDialogState();
}

class _NginxInitDialogState extends State<NginxInitDialog> {
  final _folderNameController = TextEditingController(text: 'nginx');
  final _domainController = TextEditingController();
  String _baseDir = '';
  bool _creating = false;
  bool _created = false;
  bool _installingMkcert = false;
  bool? _mkcertAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkMkcert();
  }

  Future<void> _checkMkcert() async {
    final ok = await NginxService.isMkcertAvailable();
    if (mounted) setState(() => _mkcertAvailable = ok);
  }

  Future<void> _installMkcert() async {
    setState(() {
      _installingMkcert = true;
      _logLines.clear();
    });
    final exitCode = await NginxService.installMkcert((line) {
      if (mounted) setState(() => _logLines.add(line));
    });
    if (mounted) {
      setState(() => _installingMkcert = false);
      if (exitCode == 0) {
        await _checkMkcert();
      }
    }
  }

  Future<void> _pickBaseDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.nginxInitBaseDir);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.nginxInitBaseDir);
    }
    if (path != null) setState(() => _baseDir = path!);
  }

  bool get _isValid =>
      _baseDir.isNotEmpty &&
      _folderNameController.text.trim().isNotEmpty &&
      _domainController.text.trim().isNotEmpty;

  Future<void> _create() async {
    if (!_isValid) return;
    setState(() {
      _creating = true;
      _logLines.clear();
    });

    try {
      final projectDir = await NginxService.initProject(
        baseDir: _baseDir,
        folderName: _folderNameController.text.trim(),
        domain: _domainController.text.trim(),
        onOutput: (line) {
          if (mounted) setState(() => _logLines.add(line));
        },
      );

      if (mounted) {
        setState(() {
          _creating = false;
          _created = true;
        });
        final confDir = p.join(projectDir, 'conf.d');
        widget.onCreated(confDir, _domainController.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxInitSuccess(projectDir))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _logLines.add('[ERROR] $e');
        });
      }
    }
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Text(context.l10n.nginxInitTitle),
        const Spacer(),
        AppDialog.closeButton(context, enabled: !_creating),
      ]),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(context.l10n.nginxInitSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: AppSpacing.lg),
            if (_mkcertAvailable == null)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator()))
            else if (_mkcertAvailable == false) ...[
              StatusCard(
                title: context.l10n.nginxInitMkcertRequired,
                subtitle: context.l10n.nginxInitMkcertInstall,
                status: StatusType.error,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _installingMkcert ? null : _installMkcert,
                icon: _installingMkcert
                    ? const SizedBox(
                        width: AppIconSize.md,
                        height: AppIconSize.md,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_installingMkcert
                    ? context.l10n.installing
                    : 'Install mkcert'),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
              ],
            ]
            else ...[
              // mkcert status
              Card(
                color: Colors.green.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: AppIconSize.md),
                      const SizedBox(width: AppSpacing.sm),
                      Text('mkcert',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade300)),
                      const SizedBox(width: AppSpacing.xs),
                      Text('ready', style: TextStyle(color: Colors.green.shade300)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _baseDir),
                      decoration: InputDecoration(
                        labelText: context.l10n.nginxInitBaseDir,
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _folderNameController,
                      decoration: InputDecoration(
                        labelText: context.l10n.nginxInitFolderName,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: TextField(
                      controller: _domainController,
                      decoration: InputDecoration(
                        labelText: context.l10n.nginxInitDomain,
                        hintText: context.l10n.nginxInitDomainHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
              ],
            ],
          ],
          ),
        ),
      ),
      actions: [
        if (_mkcertAvailable == true && !_created)
          FilledButton.icon(
            onPressed: (_creating || !_isValid) ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.create_new_folder),
            label: Text(_creating
                ? context.l10n.creating
                : context.l10n.nginxInitCreate),
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
