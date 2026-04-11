import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/environment_provider.dart';
import 'package:odoo_auto_config/services/git_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';
import 'package:odoo_auto_config/widgets/vscode_install_dialog.dart';
import 'home_screen.dart';

class EnvironmentScreen extends ConsumerWidget {
  const EnvironmentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(environmentProvider);
    final notifier = ref.read(environmentProvider.notifier);

    final items = _buildItems(context, ref, env);
    final checkedCount = items.where((i) => i.installed != null).length;
    final issueCount =
        items.where((i) => i.installed == false && i.required_).length;

    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(context.l10n.envSetupTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed:
                    (env.loading || env.autoInstalling) ? null : notifier.checkAll,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.envCheckAll),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: (env.loading || env.autoInstalling)
                    ? null
                    : () => _autoSetup(context, ref),
                icon: env.autoInstalling
                    ? const SizedBox(
                        width: AppIconSize.md,
                        height: AppIconSize.md,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_fix_high),
                label: Text(env.autoInstalling
                    ? context.l10n.installing
                    : context.l10n.envAutoSetup),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(context.l10n.envSetupSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: AppSpacing.xxl),
          if (env.loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                children: [
                  ...items.map((item) => _buildEnvCard(context, item)),
                  const SizedBox(height: AppSpacing.lg),
                  if (checkedCount == items.length)
                    _buildSummaryCard(context, issueCount),
                  if (env.autoLog.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    LogOutput(lines: env.autoLog, height: AppDialog.logHeightXl),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_EnvItem> _buildItems(
      BuildContext context, WidgetRef ref, EnvironmentState env) {
    final notifier = ref.read(environmentProvider.notifier);
    return [
      _EnvItem(
        icon: Icons.merge_type,
        name: context.l10n.envGit,
        description: context.l10n.envGitDesc,
        installed: env.gitInstalled,
        detail: env.gitVersion,
        required_: true,
        onAction: () => _showInstallDialog(
          context: context,
          ref: ref,
          title: context.l10n.gitInstallTitle,
          subtitle: context.l10n.gitInstallSubtitle,
          install: GitService.install,
        ),
      ),
      _EnvItem(
        icon: Icons.sailing,
        name: context.l10n.envDocker,
        description: context.l10n.envDockerDesc,
        installed: env.dockerInstalled,
        detail: env.dockerVersion,
        extraChip: env.dockerInstalled == true
            ? (
                label: env.dockerRunning == true
                    ? context.l10n.dockerRunning
                    : env.startingDocker
                        ? context.l10n.starting
                        : context.l10n.dockerStopped,
                ok: env.dockerRunning == true,
              )
            : null,
        required_: true,
        onAction: env.dockerInstalled == true && env.dockerRunning != true
            ? notifier.startDocker
            : () => HomeScreen.navigateToSettings(settingsTab: 1),
        actionLabel: env.dockerInstalled == true && env.dockerRunning != true
            ? context.l10n.startDockerDesktop
            : null,
        actionIcon: env.dockerInstalled == true && env.dockerRunning != true
            ? Icons.play_arrow
            : null,
      ),
      _EnvItem(
        icon: Icons.code,
        name: context.l10n.envPython,
        description: context.l10n.envPythonDesc,
        installed: env.pythonResults?.isNotEmpty,
        detail: env.pythonResults != null && env.pythonResults!.isNotEmpty
            ? context.l10n.envPythonVersions(env.pythonResults!.length)
            : null,
        required_: true,
        onAction: () => HomeScreen.navigateToSettings(settingsTab: 2),
      ),
      _EnvItem(
        icon: Icons.dns,
        name: context.l10n.envNginx,
        description: context.l10n.envNginxDesc,
        installed: env.hasNginxConfig,
        customLabel: env.hasNginxConfig
            ? context.l10n.envNginxConfigured
            : context.l10n.envNginxNotConfigured,
        required_: false,
        onAction: () => HomeScreen.navigateToSettings(settingsTab: 4),
      ),
      _EnvItem(
        icon: Icons.terminal,
        name: context.l10n.envVscode,
        description: context.l10n.envVscodeDesc,
        installed: env.vscodeInstalled,
        required_: false,
        onAction: () => AppDialog.show(
          context: context,
          builder: (_) => const VscodeInstallDialog(),
        ).then((_) => notifier.checkAll()),
      ),
    ];
  }

  Future<void> _autoSetup(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(environmentProvider.notifier).autoSetup();
    if (result == AutoSetupResult.needsRestart && context.mounted) {
      _showRestartDialog(context);
    }
  }

  void _showRestartDialog(BuildContext context) {
    AppDialog.show(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt, size: AppIconSize.xxxl, color: Colors.orange),
        title: Text(context.l10n.envRestartRequired),
        content: Text(context.l10n.envRestartMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              if (PlatformService.isWindows) {
                await Process.run('shutdown', ['/r', '/t', '5'],
                    runInShell: true);
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: Text(context.l10n.envRestartNow),
          ),
        ],
      ),
    );
  }

  void _showInstallDialog({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String subtitle,
    required Future<int> Function(void Function(String)) install,
  }) {
    AppDialog.show(
      context: context,
      builder: (ctx) => _InstallDialog(
        title: title,
        subtitle: subtitle,
        install: install,
        onInstalled: () => ref.read(environmentProvider.notifier).checkAll(),
      ),
    );
  }

  Widget _buildEnvCard(BuildContext context, _EnvItem item) {
    final isOk = item.installed == true;
    final isWarning = item.installed == false && !item.required_;
    final isError = item.installed == false && item.required_;
    final isLoading = item.installed == null;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Icon(item.icon,
                color: isOk
                    ? Colors.green
                    : isError
                        ? Colors.red
                        : isWarning
                            ? Colors.orange
                            : Colors.grey,
                size: AppIconSize.xl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: FontWeight.bold)),
                  Text(item.description,
                      style: TextStyle(
                          fontSize: AppFontSize.sm,
                          color: Colors.grey.shade600)),
                  if (item.detail != null)
                    Text(item.detail!,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: AppFontSize.sm,
                            color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                  width: AppIconSize.xl,
                  height: AppIconSize.xl,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              _chip(
                context,
                item.customLabel ??
                    (isOk
                        ? context.l10n.installed
                        : context.l10n.notInstalled),
                isOk,
              ),
              if (item.extraChip != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _chip(context, item.extraChip!.label, item.extraChip!.ok),
              ],
              if (!isOk || item.actionLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  onPressed: item.onAction,
                  icon: Icon(item.actionIcon ??
                      (item.required_ ? Icons.download : Icons.settings)),
                  label: Text(item.actionLabel ??
                      (item.required_
                          ? context.l10n.install
                          : context.l10n.edit)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool ok) {
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.cancel,
          size: AppIconSize.statusIcon, color: ok ? Colors.green : Colors.red),
      label: Text(label),
      backgroundColor: ok
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
    );
  }

  Widget _buildSummaryCard(BuildContext context, int issueCount) {
    return Card(
      color: issueCount == 0
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Icon(
              issueCount == 0 ? Icons.check_circle : Icons.warning,
              color: issueCount == 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              issueCount == 0
                  ? context.l10n.envAllGood
                  : context.l10n.envSomeIssues(issueCount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: issueCount == 0 ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class for environment items ──

class _EnvItem {
  final IconData icon;
  final String name;
  final String description;
  final bool? installed;
  final String? detail;
  final String? customLabel;
  final ({String label, bool ok})? extraChip;
  final bool required_;
  final VoidCallback onAction;
  final String? actionLabel;
  final IconData? actionIcon;

  const _EnvItem({
    required this.icon,
    required this.name,
    required this.description,
    required this.installed,
    this.detail,
    this.customLabel,
    this.extraChip,
    required this.required_,
    required this.onAction,
    this.actionLabel,
    this.actionIcon,
  });
}

// ── Install Dialog (local UI state only) ──

class _InstallDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<int> Function(void Function(String)) install;
  final VoidCallback onInstalled;

  const _InstallDialog({
    required this.title,
    required this.subtitle,
    required this.install,
    required this.onInstalled,
  });

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  bool _installing = false;
  bool _installed = false;
  final List<String> _logLines = [];

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    final exitCode = await widget.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    });
    if (mounted) {
      setState(() {
        _installing = false;
        _installed = exitCode == 0;
      });
      if (exitCode == 0) widget.onInstalled();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        if (!_installed)
          FilledButton.icon(
            onPressed: _installing ? null : _install,
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
