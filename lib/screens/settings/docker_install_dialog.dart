import 'dart:io';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import '../../services/docker_install_service.dart';
import '../../services/platform_service.dart';
import '../../services/python_install_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/log_output.dart';
import '../../widgets/status_card.dart';

class DockerInstallDialog extends StatefulWidget {
  final VoidCallback onInstalled;
  const DockerInstallDialog({super.key, required this.onInstalled});

  @override
  State<DockerInstallDialog> createState() => _DockerInstallDialogState();
}

class _DockerInstallDialogState extends State<DockerInstallDialog> {
  bool _installing = false;
  bool _installed = false;
  bool _needsRestart = false;
  bool? _pmAvailable;
  bool? _wslInstalled;
  final List<String> _logLines = [];

  // macOS: chọn OrbStack hoặc Docker Desktop
  String _macOsDocker = 'orbstack';

  // Start Docker after install
  bool _startingDocker = false;

  @override
  void initState() {
    super.initState();
    _checkPM();
    _checkWsl();
  }

  Future<void> _checkPM() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = ok);
  }

  Future<void> _checkWsl() async {
    if (!PlatformService.isWindows) return;
    final ok = await DockerInstallService.isWslInstalled();
    if (mounted) setState(() => _wslInstalled = ok);
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    final exitCode = await DockerInstallService.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    }, macOsDocker: _macOsDocker);
    if (mounted) {
      // Check if WSL was just installed (needs restart before Docker)
      final wslJustInstalled = _logLines.any((l) => l.contains('RESTART'));
      setState(() {
        _installing = false;
        _needsRestart = wslJustInstalled;
        _installed = exitCode == 0 && !wslJustInstalled;
      });
      if (_installed) {
        // Lưu lựa chọn Docker runtime (macOS)
        if (PlatformService.isMacOS) {
          await StorageService.updateSettings((settings) {
            settings['dockerRuntime'] = _macOsDocker;
          });
        }
        widget.onInstalled();
      }
    }
  }

  Future<void> _restart() async {
    await Process.run('shutdown', ['/r', '/t', '5'], runInShell: true);
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
        Text(context.l10n.dockerInstallTitle),
        const Spacer(),
        AppDialog.closeButton(context, enabled: !_installing),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.dockerInstallSubtitle,
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
              if (PlatformService.isWindows && _wslInstalled == false)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: StatusCard(
                    title: 'WSL not installed',
                    subtitle: 'WSL is required for Docker Desktop on Windows.\n'
                        'It will be installed first, then you need to restart your PC.',
                    status: StatusType.warning,
                  ),
                ),
              // macOS: chọn OrbStack hoặc Docker Desktop
              if (PlatformService.isMacOS && !_installing && !_installed) ...[
                Row(
                  children: [
                    Expanded(
                      child: _dockerOptionCard(
                        context,
                        value: 'orbstack',
                        title: 'OrbStack',
                        subtitle: 'Lightweight, fast',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _dockerOptionCard(
                        context,
                        value: 'docker',
                        title: 'Docker Desktop',
                        subtitle: 'Official Docker app',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(DockerInstallService.installCommand(
                      macOsDocker: _macOsDocker)
                  .description,
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
        if (_needsRestart)
          FilledButton.icon(
            onPressed: _restart,
            icon: const Icon(Icons.restart_alt),
            label: Text(context.l10n.envRestartNow),
          )
        else if (_installed)
          FilledButton.icon(
            onPressed: _startingDocker ? null : _startDocker,
            icon: _startingDocker
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(_startingDocker
                ? context.l10n.starting
                : 'Start Docker'),
          )
        else if (_pmAvailable == true)
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_installing
                ? context.l10n.installing
                : context.l10n.dockerInstall),
          ),
      ],
    );
  }

  Widget _dockerOptionCard(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
  }) {
    final selected = _macOsDocker == value;
    return GestureDetector(
      onTap: () => setState(() => _macOsDocker = value),
      child: Card(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: AppFontSize.sm, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startDocker() async {
    setState(() => _startingDocker = true);
    try {
      await DockerInstallService.startDaemon();
      setState(() {
        _logLines.add('');
        _logLines.add('[+] Docker is starting...');
        _startingDocker = false;
      });
    } catch (e) {
      setState(() {
        _logLines.add('[ERROR] $e');
        _startingDocker = false;
      });
    }
  }
}
