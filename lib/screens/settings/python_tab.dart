import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/models/python_info.dart';
import 'package:odoo_auto_config/providers/settings_provider.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/status_card.dart';
import 'package:odoo_auto_config/screens/venv_screen.dart';
import 'python_install_dialog.dart';
import 'python_uninstall_dialog.dart';

class PythonTab extends ConsumerStatefulWidget {
  const PythonTab({super.key});

  @override
  ConsumerState<PythonTab> createState() => _PythonTabState();
}

class _PythonTabState extends ConsumerState<PythonTab>
    with TickerProviderStateMixin {
  late final TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          tabs: [
            Tab(
                icon: const Icon(Icons.code),
                text: context.l10n.pythonCheckTitle),
            const Tab(icon: Icon(Icons.terminal), text: 'Venv'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              _buildPythonCheckSubTab(),
              const VenvScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPythonCheckSubTab() {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(context.l10n.pythonCheckTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: s.pythonLoading ? null : () => _importPython(notifier),
                icon: const Icon(Icons.folder_open),
                label: Text(context.l10n.importPython),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonalIcon(
                onPressed: s.pythonLoading
                    ? null
                    : () => _showPythonInstallDialog(notifier, s),
                icon: const Icon(Icons.download),
                label: Text(context.l10n.installPython),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed:
                    s.pythonLoading ? null : () => notifier.scanEnvironment(),
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.rescan,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (s.pythonLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              ),
            )
          else if (s.pythonResults != null && s.pythonResults!.isEmpty)
            StatusCard(
              title: context.l10n.noPythonFound,
              subtitle: context.l10n.noPythonFoundSubtitle,
              status: StatusType.warning,
            )
          else if (s.pythonResults != null)
            ...(s.pythonResults!.map((info) {
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    children: [
                      const Icon(Icons.code, color: Colors.blue),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.pythonVersion(info.version),
                              style: const TextStyle(
                                  fontSize: AppFontSize.lg,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(info.executablePath,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      _envChip(
                          context.l10n.pipVersion(info.pipVersion),
                          info.hasPip),
                      const SizedBox(width: AppSpacing.sm),
                      _envChip(context.l10n.venvModule, info.hasVenv),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton(
                        onPressed: () =>
                            _showPythonUninstallDialog(notifier, info),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: context.l10n.uninstallPython,
                        color: Colors.red.shade300,
                        iconSize: AppIconSize.md,
                      ),
                    ],
                  ),
                ),
              );
            })),
        ],
      ),
    );
  }

  String _majorMinor(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return version;
  }

  Future<void> _importPython(SettingsNotifier notifier) async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickFile(
        dialogTitle: context.l10n.importPythonTitle,
        filter: 'Executable (*.exe)|*.exe',
      );
    } else {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: context.l10n.importPythonTitle,
        type: FileType.any,
      );
      path = result?.files.single.path;
    }
    if (path == null || !mounted) return;

    final s = ref.read(settingsProvider);
    final info = await notifier.pythonChecker.checkPython(path);
    if (!mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPythonInvalid)),
      );
      return;
    }

    final isDuplicate = s.pythonResults?.any(
          (r) =>
              r.executablePath == info.executablePath ||
              r.version == info.version,
        ) ??
        false;
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPythonDuplicate)),
      );
      return;
    }

    notifier.addPythonResult(info);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.importPythonSuccess(info.version))),
    );
  }

  void _showPythonInstallDialog(
      SettingsNotifier notifier, SettingsState s) {
    AppDialog.show(
      context: context,
      builder: (ctx) => PythonInstallDialog(
        installedVersions:
            s.pythonResults?.map((r) => _majorMinor(r.version)).toSet() ?? {},
        onInstalled: () => notifier.scanEnvironment(),
      ),
    );
  }

  void _showPythonUninstallDialog(
      SettingsNotifier notifier, PythonInfo info) {
    final parts = info.version.split('.');
    final majorMinor =
        parts.length >= 2 ? '${parts[0]}.${parts[1]}' : info.version;

    AppDialog.show(
      context: context,
      builder: (ctx) => PythonUninstallDialog(
        version: majorMinor,
        fullVersion: info.version,
        executablePath: info.executablePath,
        onUninstalled: () => notifier.scanEnvironment(),
      ),
    );
  }

  Widget _envChip(String label, bool ok) {
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.cancel,
          size: 18, color: ok ? Colors.green : Colors.red),
      label: Text(label),
      backgroundColor: ok
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
    );
  }
}
