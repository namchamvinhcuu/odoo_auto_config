import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/settings_provider.dart';
import 'package:odoo_auto_config/services/postgres_service.dart';
import 'pg_setup_dialog.dart';
import 'postgres_install_dialog.dart';

class PostgresTab extends ConsumerWidget {
  const PostgresTab({super.key});

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
              Text(context.l10n.postgresStatus,
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton.filled(
                onPressed:
                    s.pythonLoading ? null : () => notifier.scanEnvironment(),
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.rescan,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(context.l10n.postgresClientNote,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: AppSpacing.lg),
          if (s.pgInstalled == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            // Status card
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  children: [
                    Icon(Icons.storage,
                        color:
                            s.pgInstalled == true ? Colors.blue : Colors.grey,
                        size: AppIconSize.xxl),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PostgreSQL Client',
                              style: TextStyle(
                                  fontSize: AppFontSize.xl,
                                  fontWeight: FontWeight.bold)),
                          if (s.pgVersion != null)
                            Text(s.pgVersion!,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    if (s.pgInstalled == true) ...[
                      _envChip(context.l10n.postgresInstalled, true),
                    ] else ...[
                      _envChip(context.l10n.postgresNotInstalled, false),
                      const SizedBox(width: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: () =>
                            _showPostgresInstallDialog(context, notifier),
                        icon: const Icon(Icons.download),
                        label: Text(context.l10n.postgresInstall),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Client tools detail
            if (s.pgTools != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(context.l10n.postgresClientTools,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    children: PostgresService.clientTools.map((tool) {
                      final (name, desc) = tool;
                      final path = s.pgTools![name];
                      final available = path != null;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs),
                        child: Row(
                          children: [
                            Icon(
                              available
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: AppIconSize.statusIcon,
                              color:
                                  available ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 100,
                              child: Text(name,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppFontSize.sm)),
                            ),
                            Expanded(
                              child: Text(desc,
                                  style: TextStyle(
                                      fontSize: AppFontSize.sm,
                                      color: Colors.grey.shade600)),
                            ),
                            if (available)
                              Flexible(
                                child: Text(path,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: AppFontSize.xs,
                                        color: Colors.grey.shade500),
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (s.pgInstalled != true) ...[
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _showPostgresInstallDialog(context, notifier),
                    icon: const Icon(Icons.download),
                    label: Text(context.l10n.postgresInstall),
                  ),
                ),
              ],
            ],
            // Server Status
            const SizedBox(height: AppSpacing.xl),
            Text(context.l10n.postgresServerStatus,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (s.pgServers == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (s.pgServers!.isEmpty)
              Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.orange, size: AppIconSize.lg),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(context.l10n.postgresNoServer,
                            style: TextStyle(color: Colors.grey.shade600)),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: () =>
                            _showPgSetupDialog(context, notifier),
                        icon: const Icon(Icons.add),
                        label: Text(context.l10n.postgresSetupDocker),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(s.pgServers!.map((server) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _buildServerCard(context, ref, server),
                  ))),
          ],
        ],
      ),
    );
  }

  void _showPostgresInstallDialog(
      BuildContext context, SettingsNotifier notifier) {
    AppDialog.show(
      context: context,
      builder: (ctx) => PostgresInstallDialog(
        onInstalled: () => notifier.scanEnvironment(),
      ),
    );
  }

  void _showPgSetupDialog(BuildContext context, SettingsNotifier notifier) {
    AppDialog.show(
      context: context,
      builder: (ctx) => PgSetupDialog(
        onCreated: () => notifier.scanEnvironment(),
      ),
    );
  }

  Widget _buildServerCard(
      BuildContext context, WidgetRef ref, PgServerInfo server) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final isDocker = server.source == PgServerSource.docker;
    final isRunning =
        isDocker ? (server.containerRunning == true) : server.isReady;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Icon(
              isDocker ? Icons.sailing : Icons.computer,
              color: isRunning ? Colors.blue : Colors.grey,
              size: AppIconSize.lg,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDocker ? 'Docker' : 'Local',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (server.containerName != null)
                    Text(
                      '${context.l10n.postgresContainer}: ${server.containerName}',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.sm,
                          color: Colors.grey.shade600),
                    ),
                  if (server.imageName != null)
                    Text(
                      '${context.l10n.postgresImage}: ${server.imageName}',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.sm,
                          color: Colors.grey.shade600),
                    ),
                  if (server.serviceName != null)
                    Text(
                      '${context.l10n.postgresService}: ${server.serviceName}',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: AppFontSize.sm,
                          color: Colors.grey.shade600),
                    ),
                  Text(
                    '${context.l10n.postgresPort}: ${server.port}',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: AppFontSize.sm,
                        color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            // Status chips
            if (isDocker) ...[
              _envChip(
                isRunning
                    ? context.l10n.postgresContainerRunning
                    : context.l10n.postgresContainerStopped,
                isRunning,
              ),
              if (server.isReady)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: _envChip(context.l10n.postgresReady, true),
                ),
            ] else ...[
              _envChip(
                server.isReady
                    ? context.l10n.postgresReady
                    : context.l10n.postgresNotReady,
                server.isReady,
              ),
            ],
            // Action buttons
            const SizedBox(width: AppSpacing.md),
            if (isDocker && server.containerName != null) ...[
              if (isRunning) ...[
                IconButton(
                  onPressed: s.pgActionLoading
                      ? null
                      : () => notifier.pgContainerAction(
                            server.containerName!,
                            PostgresService.stopContainer,
                          ),
                  icon: const Icon(Icons.stop),
                  tooltip: 'Stop',
                  color: Colors.red,
                ),
                IconButton(
                  onPressed: s.pgActionLoading
                      ? null
                      : () => notifier.pgContainerAction(
                            server.containerName!,
                            PostgresService.restartContainer,
                          ),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Restart',
                ),
              ] else
                IconButton(
                  onPressed: s.pgActionLoading
                      ? null
                      : () => notifier.pgContainerAction(
                            server.containerName!,
                            PostgresService.startContainer,
                          ),
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Start',
                  color: Colors.green,
                ),
            ] else if (!isDocker && !server.isReady)
              IconButton(
                onPressed:
                    s.pgActionLoading ? null : () => notifier.pgLocalStartAction(),
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Start',
                color: Colors.green,
              ),
            if (s.pgActionLoading)
              const SizedBox(
                width: AppIconSize.xl,
                height: AppIconSize.xl,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
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
