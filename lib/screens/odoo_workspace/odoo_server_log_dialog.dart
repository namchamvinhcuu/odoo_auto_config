import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/odoo_servers_provider.dart';
import 'package:odoo_auto_config/services/odoo_launch_config_service.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

/// Runs an Odoo server (like VSCode F5) and streams its log.
///
/// On open it launches (or restarts, if already running) the server for
/// [projectPath]; once the "HTTP running" line appears it auto-opens the
/// project in the browser (nginx subdomain). The server keeps running in the
/// [runningServersProvider] even after this dialog is closed.
class OdooServerLogDialog extends ConsumerStatefulWidget {
  final String projectName;
  final String projectPath;
  final String? nginxSubdomain;
  final OdooLaunchConfig config;

  const OdooServerLogDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
    required this.config,
    this.nginxSubdomain,
  });

  bool get hasNginx =>
      nginxSubdomain != null && nginxSubdomain!.isNotEmpty;

  @override
  ConsumerState<OdooServerLogDialog> createState() =>
      _OdooServerLogDialogState();
}

class _OdooServerLogDialogState extends ConsumerState<OdooServerLogDialog> {
  bool _browserOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  /// Start/restart the server. The browser is opened by the [ref.listen] in
  /// [build] when the status transitions to ready (no time limit — a slow
  /// first boot still triggers it).
  Future<void> _launch() async {
    _browserOpened = false;
    await ref
        .read(runningServersProvider.notifier)
        .launch(widget.projectPath, widget.config);
  }

  Future<void> _stop() =>
      ref.read(runningServersProvider.notifier).stop(widget.projectPath);

  void _clear() =>
      ref.read(runningServersProvider.notifier).clearLogs(widget.projectPath);

  Future<void> _openBrowser() async {
    if (!widget.hasNginx) return;
    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    final dotSuffix = suffix.startsWith('.') ? suffix : '.$suffix';
    final url = 'https://${widget.nginxSubdomain}$dotSuffix';
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url], runInShell: true);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', url], runInShell: true);
      } else {
        await Process.run('xdg-open', [url], runInShell: true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Auto-open the browser once, the moment the server reports ready.
    ref.listen(runningServersProvider, (prev, next) {
      final was = prev?[widget.projectPath]?.status;
      final now = next[widget.projectPath]?.status;
      if (now == OdooServerStatus.ready &&
          was != OdooServerStatus.ready &&
          !_browserOpened) {
        _browserOpened = true;
        _openBrowser();
      }
    });

    final st = ref.watch(runningServersProvider)[widget.projectPath] ??
        const OdooServerState();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.dns),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(context.l10n.odooServerTitle(widget.projectName)),
          ),
          const SizedBox(width: AppSpacing.sm),
          _statusChip(context, st.status),
          const SizedBox(width: AppSpacing.md),
          _actionButton(
            context,
            icon: Icons.restart_alt,
            color: Theme.of(context).colorScheme.primary,
            tooltip: context.l10n.restartServer,
            onPressed: _launch,
          ),
          const SizedBox(width: AppSpacing.sm),
          _actionButton(
            context,
            icon: Icons.stop,
            color: Colors.red.shade700,
            tooltip: context.l10n.stopServer,
            onPressed: st.isActive ? _stop : null,
          ),
          if (widget.hasNginx) ...[
            const SizedBox(width: AppSpacing.sm),
            _actionButton(
              context,
              icon: Icons.language,
              color: Theme.of(context).colorScheme.tertiary,
              tooltip: context.l10n.openInBrowser,
              onPressed: _openBrowser,
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          _actionButton(
            context,
            icon: Icons.clear_all,
            color: Colors.blueGrey,
            tooltip: context.l10n.clearLogs,
            onPressed: st.logs.isEmpty ? null : _clear,
          ),
          const SizedBox(width: AppSpacing.sm),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthXl,
        child: LogOutput(
          lines: st.logs,
          height: AppDialog.logHeightXl,
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, OdooServerStatus status) {
    final (label, color) = switch (status) {
      OdooServerStatus.starting => (
          context.l10n.serverStatusStarting,
          Colors.amber.shade700,
        ),
      OdooServerStatus.ready => (
          context.l10n.serverStatusRunning,
          Colors.green.shade600,
        ),
      OdooServerStatus.stopped => (
          context.l10n.serverStatusStopped,
          Colors.grey.shade600,
        ),
      OdooServerStatus.error => (
          context.l10n.serverStatusError,
          Colors.red.shade700,
        ),
      OdooServerStatus.idle => (
          context.l10n.serverStatusIdle,
          Colors.grey.shade600,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: AppFontSize.sm,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: AppIconSize.md),
      style: IconButton.styleFrom(
        backgroundColor: onPressed == null ? Colors.grey : color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
        padding: EdgeInsets.zero,
      ),
      tooltip: tooltip,
    );
  }
}
