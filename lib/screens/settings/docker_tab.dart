import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/settings_provider.dart';
import 'docker_install_dialog.dart';

class DockerTab extends ConsumerWidget {
  const DockerTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(context.l10n.dockerStatus,
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton.filled(
                onPressed: s.pythonLoading ? null : () => notifier.scanEnvironment(),
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.rescan,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (s.dockerInstalled == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  children: [
                    Icon(Icons.sailing,
                        color: s.dockerInstalled == true
                            ? Colors.blue
                            : Colors.grey,
                        size: AppIconSize.xxl),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Docker',
                              style: TextStyle(
                                  fontSize: AppFontSize.xl,
                                  fontWeight: FontWeight.bold)),
                          if (s.dockerVersion != null)
                            Text(s.dockerVersion!,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                          if (s.dockerComposeVersion != null)
                            Text(s.dockerComposeVersion!,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    if (s.dockerInstalled == true) ...[
                      _envChip(context.l10n.dockerInstalled, true),
                      const SizedBox(width: AppSpacing.sm),
                      _envChip(
                        s.dockerRunning == true
                            ? context.l10n.dockerRunning
                            : context.l10n.dockerStopped,
                        s.dockerRunning == true,
                      ),
                      if (s.dockerRunning != true) ...[
                        const SizedBox(width: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed:
                              s.startingDocker ? null : () => notifier.startDocker(),
                          icon: s.startingDocker
                              ? const SizedBox(
                                  width: AppIconSize.md,
                                  height: AppIconSize.md,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow),
                          label: Text(s.startingDocker
                              ? context.l10n.starting
                              : context.l10n.startDockerDesktop),
                        ),
                      ],
                    ] else ...[
                      _envChip(context.l10n.dockerNotInstalled, false),
                      const SizedBox(width: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: () => _showDockerInstallDialog(context, notifier),
                        icon: const Icon(Icons.download),
                        label: Text(context.l10n.dockerInstall),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDockerInstallDialog(
      BuildContext context, SettingsNotifier notifier) {
    AppDialog.show(
      context: context,
      builder: (ctx) =>
          DockerInstallDialog(onInstalled: () => notifier.scanEnvironment()),
    );
  }

  Widget _envChip(String label, bool ok) {
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.cancel,
          size: AppIconSize.statusIcon, color: ok ? Colors.green : Colors.red),
      label: Text(label),
      backgroundColor: ok
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
    );
  }
}
