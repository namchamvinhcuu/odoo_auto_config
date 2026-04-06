import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import '../../services/platform_service.dart';
import '../../services/postgres_service.dart';
import '../../services/python_install_service.dart';
import '../../widgets/log_output.dart';
import '../../widgets/status_card.dart';

class PostgresInstallDialog extends StatefulWidget {
  final VoidCallback onInstalled;
  const PostgresInstallDialog({super.key, required this.onInstalled});

  @override
  State<PostgresInstallDialog> createState() => _PostgresInstallDialogState();
}

class _PostgresInstallDialogState extends State<PostgresInstallDialog> {
  bool _installing = false;
  bool _installed = false;
  bool? _pmAvailable;
  String? _installDescription;
  int? _selectedVersion;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _selectedVersion = PlatformService.isWindows ? PostgresService.availableVersions.first : null;
    _init();
  }

  Future<void> _init() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    final cmd = await PostgresService.installCommand(version: _selectedVersion);
    if (mounted) {
      setState(() {
        _pmAvailable = ok;
        _installDescription = cmd.description;
      });
    }
  }

  Future<void> _updateDescription() async {
    final cmd = await PostgresService.installCommand(version: _selectedVersion);
    if (mounted) setState(() => _installDescription = cmd.description);
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    final exitCode = await PostgresService.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    }, version: _selectedVersion);
    if (mounted) {
      setState(() {
        _installing = false;
        _installed = exitCode == 0;
      });
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
        Text(context.l10n.postgresInstallTitle),
        const Spacer(),
        AppDialog.closeButton(context, enabled: !_installing),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.postgresInstallSubtitle,
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
              if (PlatformService.isWindows) ...[
                Text(context.l10n.selectVersion,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: PostgresService.availableVersions.map((v) {
                    return ChoiceChip(
                      label: Text('PostgreSQL $v'),
                      selected: _selectedVersion == v,
                      onSelected: _installing
                          ? null
                          : (sel) {
                              setState(() => _selectedVersion = sel ? v : null);
                              _updateDescription();
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_installDescription != null)
                Text(_installDescription!,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: AppFontSize.sm,
                        color: Colors.grey.shade600)),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (_pmAvailable == true)
          _installed
              ? FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: Text(context.l10n.close),
                )
              : FilledButton.icon(
                  onPressed: _installing ? null : _install,
                  icon: _installing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(_installing
                      ? context.l10n.installing
                      : context.l10n.postgresInstall),
                ),
      ],
    );
  }
}
