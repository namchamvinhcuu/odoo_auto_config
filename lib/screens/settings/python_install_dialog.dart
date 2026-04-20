import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/python_install_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';
import 'package:odoo_auto_config/widgets/status_card.dart';

class PythonInstallDialog extends StatefulWidget {
  final Set<String> installedVersions;
  final VoidCallback onInstalled;

  const PythonInstallDialog({
    super.key,
    required this.installedVersions,
    required this.onInstalled,
  });

  @override
  State<PythonInstallDialog> createState() => _PythonInstallDialogState();
}

class _PythonInstallDialogState extends State<PythonInstallDialog> {
  String? _selectedVersion;
  bool _installing = false;
  bool? _pmAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkPM();
  }

  Future<void> _checkPM() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = ok);
  }

  Future<void> _install() async {
    if (_selectedVersion == null) return;
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    context.setDialogRunning(true);
    final exitCode = await PythonInstallService.install(
      _selectedVersion!,
      (line) {
        if (mounted) setState(() => _logLines.add(line));
      },
    );
    if (mounted) {
      setState(() => _installing = false);
      context.setDialogRunning(false);
      if (exitCode == 0) widget.onInstalled();
    }
  }

  String _pmNotFound(BuildContext context) {
    if (PlatformService.isWindows) {
      return context.l10n.packageManagerNotFoundWindows;
    }
    if (PlatformService.isMacOS) return context.l10n.packageManagerNotFoundMac;
    return context.l10n.packageManagerNotFoundLinux;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Text(context.l10n.installPythonTitle),
        const Spacer(),
        AppDialog.closeButton(context),
      ]),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: AppDialog.contentMaxHeight(context),
            ),
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(context.l10n.installPythonSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: AppSpacing.lg),
            if (_pmAvailable == null)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator()))
            else if (_pmAvailable == false)
              StatusCard(
                  title: context.l10n.packageManagerNotFound,
                  subtitle: _pmNotFound(context),
                  status: StatusType.error)
            else ...[
              Text(context.l10n.selectVersion,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children:
                    PythonInstallService.availableVersions.map((v) {
                  final installed =
                      widget.installedVersions.contains(v.version);
                  return ChoiceChip(
                    label: Text(installed ? '${v.label} ✓' : v.label),
                    selected: _selectedVersion == v.version,
                    onSelected: (_installing || installed)
                        ? null
                        : (s) => setState(
                            () => _selectedVersion = s ? v.version : null),
                  );
                }).toList(),
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
      ),
      actions: [
        if (_pmAvailable == true)
          FilledButton.icon(
            onPressed:
                (_installing || _selectedVersion == null) ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(
                _installing ? context.l10n.installing : context.l10n.install),
          ),
      ],
    );
  }
}
