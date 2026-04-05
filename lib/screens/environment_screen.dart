import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/python_info.dart';
import '../services/docker_install_service.dart';
import '../services/git_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/python_checker_service.dart';
import '../services/python_install_service.dart';
import '../widgets/log_output.dart';
import '../widgets/vscode_install_dialog.dart';
import 'home_screen.dart';

class EnvironmentScreen extends StatefulWidget {
  const EnvironmentScreen({super.key});

  @override
  State<EnvironmentScreen> createState() => _EnvironmentScreenState();
}

class _EnvironmentScreenState extends State<EnvironmentScreen> {
  final _pythonChecker = PythonCheckerService();
  bool _loading = false;
  bool _autoInstalling = false;
  final List<String> _autoLog = [];

  bool? _gitInstalled;
  String? _gitVersion;
  bool? _dockerInstalled;
  bool? _dockerRunning;
  String? _dockerVersion;
  List<PythonInfo>? _pythonResults;
  bool _hasNginxConfig = false;
  bool? _vscodeInstalled;
  bool _startingDocker = false;

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        GitService.isInstalled(),
        GitService.getVersion(),
        DockerInstallService.isInstalled(),
        _pythonChecker.detectAll(),
        PlatformService.isVscodeInstalled(),
        NginxService.loadSettings(),
      ]);

      final gitOk = results[0] as bool;
      final gitVer = results[1] as String?;
      final dockerOk = results[2] as bool;
      final pyResults = results[3] as List<PythonInfo>;
      final vsOk = results[4] as bool;
      final nginx = results[5] as Map<String, dynamic>;

      final dockerRunning =
          dockerOk ? await DockerInstallService.isRunning() : false;
      final dockerVer =
          dockerOk ? await DockerInstallService.getVersion() : null;

      if (mounted) {
        setState(() {
          _gitInstalled = gitOk;
          _gitVersion = gitVer;
          _dockerInstalled = dockerOk;
          _dockerRunning = dockerRunning;
          _dockerVersion = dockerVer;
          _pythonResults = pyResults;
          _vscodeInstalled = vsOk;
          _hasNginxConfig =
              (nginx['confDir'] ?? '').toString().isNotEmpty;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startDockerDesktop() async {
    setState(() => _startingDocker = true);
    try {
      if (PlatformService.isWindows) {
        await Process.run(
          'powershell',
          ['-Command', 'Start-Process', r'"C:\Program Files\Docker\Docker\Docker Desktop.exe"'],
          runInShell: true,
        );
      } else if (PlatformService.isMacOS) {
        await Process.run('open', ['-a', 'Docker'], runInShell: true);
      } else {
        await Process.run('systemctl', ['--user', 'start', 'docker-desktop'],
            runInShell: true);
      }
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await DockerInstallService.isRunning()) break;
      }
    } catch (_) {}
    await _checkAll();
    if (mounted) setState(() => _startingDocker = false);
  }

  Future<void> _autoSetup() async {
    setState(() {
      _autoInstalling = true;
      _autoLog.clear();
    });

    void log(String line) {
      if (mounted) setState(() => _autoLog.add(line));
    }

    // 1. Git
    await _checkAll();
    if (_gitInstalled != true) {
      log('');
      log('━━━ Git ━━━');
      await GitService.install(log);
      await _checkAll();
    }

    // 2. Python (3.11 for Odoo 17 compatibility)
    if (_pythonResults == null || _pythonResults!.isEmpty) {
      log('');
      log('━━━ Python ━━━');
      await PythonInstallService.install('3.11', log);
      await _checkAll();
    }

    // 3. VSCode
    if (_vscodeInstalled != true) {
      log('');
      log('━━━ VSCode ━━━');
      final cmd = PlatformService.vscodeInstallCommand();
      log('[+] Running: ${cmd.description}');
      try {
        final result = await Process.run(
          cmd.executable,
          cmd.args,
          runInShell: true,
        );
        if (result.exitCode == 0) {
          log('[+] VSCode installed successfully!');
        } else {
          log('[ERROR] VSCode installation failed');
        }
      } catch (e) {
        log('[ERROR] $e');
      }
      await _checkAll();
    }

    // 4. Docker — last because WSL may require restart on Windows
    if (_dockerInstalled != true) {
      log('');
      log('━━━ Docker ━━━');
      if (PlatformService.isWindows) {
        final wslOk = await DockerInstallService.isWslInstalled();
        if (!wslOk) {
          log('[+] WSL not found. Installing WSL...');
          await DockerInstallService.install(log);
          if (mounted) {
            setState(() => _autoInstalling = false);
            _showRestartDialog();
          }
          return;
        }
      }
      await DockerInstallService.install(log);
      await _checkAll();
    }

    // Done
    log('');
    log('[+] Auto setup complete!');
    if (mounted) setState(() => _autoInstalling = false);
  }

  void _showRestartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt, size: 48, color: Colors.orange),
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
                await Process.run('shutdown', ['/r', '/t', '5'], runInShell: true);
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: Text(context.l10n.envRestartNow),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <_EnvItem>[
      _EnvItem(
        icon: Icons.merge_type,
        name: context.l10n.envGit,
        description: context.l10n.envGitDesc,
        installed: _gitInstalled,
        detail: _gitVersion,
        required_: true,
        onAction: () => _showInstallDialog(
          title: context.l10n.gitInstallTitle,
          subtitle: context.l10n.gitInstallSubtitle,
          install: GitService.install,
        ),
      ),
      _EnvItem(
        icon: Icons.sailing,
        name: context.l10n.envDocker,
        description: context.l10n.envDockerDesc,
        installed: _dockerInstalled,
        detail: _dockerVersion,
        extraChip: _dockerInstalled == true
            ? (
                label: _dockerRunning == true
                    ? context.l10n.dockerRunning
                    : _startingDocker
                        ? context.l10n.starting
                        : context.l10n.dockerStopped,
                ok: _dockerRunning == true,
              )
            : null,
        required_: true,
        onAction: _dockerInstalled == true && _dockerRunning != true
            ? _startDockerDesktop
            : () => HomeScreen.navigateToSettings(settingsTab: 1),
        actionLabel: _dockerInstalled == true && _dockerRunning != true
            ? context.l10n.startDockerDesktop
            : null,
        actionIcon: _dockerInstalled == true && _dockerRunning != true
            ? Icons.play_arrow
            : null,
      ),
      _EnvItem(
        icon: Icons.code,
        name: context.l10n.envPython,
        description: context.l10n.envPythonDesc,
        installed: _pythonResults?.isNotEmpty,
        detail: _pythonResults != null && _pythonResults!.isNotEmpty
            ? context.l10n.envPythonVersions(_pythonResults!.length)
            : null,
        required_: true,
        onAction: () =>
            HomeScreen.navigateToSettings(settingsTab: 2), // Python tab
      ),
      _EnvItem(
        icon: Icons.dns,
        name: context.l10n.envNginx,
        description: context.l10n.envNginxDesc,
        installed: _hasNginxConfig,
        customLabel: _hasNginxConfig
            ? context.l10n.envNginxConfigured
            : context.l10n.envNginxNotConfigured,
        required_: false,
        onAction: () =>
            HomeScreen.navigateToSettings(settingsTab: 4), // Nginx tab
      ),
      _EnvItem(
        icon: Icons.terminal,
        name: context.l10n.envVscode,
        description: context.l10n.envVscodeDesc,
        installed: _vscodeInstalled,
        required_: false,
        onAction: () => showDialog(
          context: context,
          builder: (_) => const VscodeInstallDialog(),
        ).then((_) => _checkAll()),
      ),
    ];

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
                onPressed: (_loading || _autoInstalling) ? null : _checkAll,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.envCheckAll),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: (_loading || _autoInstalling) ? null : _autoSetup,
                icon: _autoInstalling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_fix_high),
                label: Text(_autoInstalling
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
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  ...items.map(_buildEnvCard),
                  const SizedBox(height: AppSpacing.lg),
                  if (checkedCount == items.length)
                    Card(
                      color: issueCount == 0
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: Row(
                          children: [
                            Icon(
                              issueCount == 0
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color: issueCount == 0
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              issueCount == 0
                                  ? context.l10n.envAllGood
                                  : context.l10n.envSomeIssues(issueCount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: issueCount == 0
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_autoLog.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    LogOutput(lines: _autoLog, height: 300),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEnvCard(_EnvItem item) {
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
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              _chip(
                item.customLabel ??
                    (isOk
                        ? context.l10n.installed
                        : context.l10n.notInstalled),
                isOk,
              ),
              if (item.extraChip != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _chip(item.extraChip!.label, item.extraChip!.ok),
              ],
              if (!isOk || item.actionLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonalIcon(
                  onPressed: item.onAction,
                  icon: Icon(
                      item.actionIcon ??
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

  Widget _chip(String label, bool ok) {
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.cancel,
          size: 18, color: ok ? Colors.green : Colors.red),
      label: Text(label),
      backgroundColor: ok
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
    );
  }

  void _showInstallDialog({
    required String title,
    required String subtitle,
    required Future<int> Function(void Function(String)) install,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _InstallDialog(
        title: title,
        subtitle: subtitle,
        install: install,
        onInstalled: () => _checkAll(),
      ),
    );
  }
}

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
        width: 520,
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
              LogOutput(lines: _logLines, height: 200),
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
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(
                _installing ? context.l10n.installing : context.l10n.install),
          ),
      ],
    );
  }
}
