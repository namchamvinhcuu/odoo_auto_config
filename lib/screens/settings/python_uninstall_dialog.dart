import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/python_install_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class PythonUninstallDialog extends StatefulWidget {
  final String version;
  final String fullVersion;
  final String executablePath;
  final VoidCallback onUninstalled;

  const PythonUninstallDialog({
    super.key,
    required this.version,
    required this.fullVersion,
    required this.executablePath,
    required this.onUninstalled,
  });

  @override
  State<PythonUninstallDialog> createState() =>
      _PythonUninstallDialogState();
}

class _PythonUninstallDialogState extends State<PythonUninstallDialog> {
  bool _uninstalling = false;
  bool _uninstalled = false;
  final List<String> _logLines = [];

  Future<void> _uninstall() async {
    setState(() {
      _uninstalling = true;
      _logLines.clear();
    });
    final exitCode = await PythonInstallService.uninstall(
      widget.version,
      (line) {
        if (mounted) setState(() => _logLines.add(line));
      },
    );
    if (mounted) {
      setState(() {
        _uninstalling = false;
        _uninstalled = exitCode == 0;
      });
      if (exitCode == 0) widget.onUninstalled();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Text(context.l10n.uninstallPython),
        const Spacer(),
        AppDialog.closeButton(context, enabled: !_uninstalling),
      ]),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            if (!_uninstalling && !_uninstalled) ...[
              Text(
                context.l10n.uninstallPythonConfirm(widget.fullVersion),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.executablePath,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.sm,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
            ],
          ],
          ),
        ),
      ),
      actions: [
        if (_uninstalled)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text(context.l10n.close),
          )
        else
          FilledButton.icon(
            onPressed: _uninstalling ? null : _uninstall,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            icon: _uninstalling
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete),
            label: Text(
              _uninstalling
                  ? context.l10n.uninstalling
                  : context.l10n.uninstallPython,
            ),
          ),
      ],
    );
  }
}
