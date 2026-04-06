import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'nginx_init_dialog.dart';

class NginxTab extends ConsumerStatefulWidget {
  const NginxTab({super.key});

  @override
  ConsumerState<NginxTab> createState() => _NginxTabState();
}

class _NginxTabState extends ConsumerState<NginxTab> {
  final _confDirController = TextEditingController();
  final _domainSuffixController = TextEditingController();
  final _containerNameController = TextEditingController();

  bool _editingNginx = false;
  List<({int port, String? process, int? pid, String source})>? _portConflicts;
  bool? _dockerNginxRunning;
  bool _checkingPorts = false;
  bool _restartingNginx = false;
  String? _nginxError;

  bool get _hasNginxConfig => _confDirController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadNginxSettings();
  }

  @override
  void dispose() {
    _confDirController.dispose();
    _domainSuffixController.dispose();
    _containerNameController.dispose();
    super.dispose();
  }

  // ── Nginx settings ──

  Future<void> _loadNginxSettings() async {
    final nginx = await NginxService.loadSettings();
    _confDirController.text = (nginx['confDir'] ?? '').toString();
    _domainSuffixController.text = (nginx['domainSuffix'] ?? '').toString();
    _containerNameController.text =
        (nginx['containerName'] ?? 'nginx').toString();
    if (mounted) {
      setState(() {}); // rebuild to update _hasNginxConfig
      if (_hasNginxConfig) _checkPorts();
    }
  }

  Future<void> _saveNginxSettings() async {
    await NginxService.saveSettings({
      'confDir': _confDirController.text.trim(),
      'domainSuffix': _domainSuffixController.text.trim(),
      'containerName': _containerNameController.text.trim(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nginxSaved)),
      );
    }
  }

  Future<void> _pickConfDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.nginxConfDir);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.nginxConfDir);
    }
    if (path != null) _confDirController.text = path;
  }

  // ── Port check ──

  Future<void> _checkPorts() async {
    setState(() => _checkingPorts = true);
    final result = await NginxService.checkNginxPorts(
        _containerNameController.text.trim().isEmpty
            ? 'nginx'
            : _containerNameController.text.trim());
    if (mounted) {
      setState(() {
        _portConflicts = result.conflicts;
        _dockerNginxRunning = result.dockerNginxRunning;
        _checkingPorts = false;
      });
    }
  }

  // ── Docker commands ──

  Future<void> _dockerCommand(String command) async {
    final container = _containerNameController.text.trim();
    if (container.isEmpty) return;
    setState(() => _restartingNginx = true);
    try {
      final result = await Process.run(
          await PlatformService.dockerPath, [command, container],
          runInShell: true);
      if (mounted) {
        if (result.exitCode != 0) {
          setState(() => _nginxError = result.stderr.toString().trim());
        } else {
          setState(() => _nginxError = null);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _nginxError = e.toString());
    }
    if (mounted) {
      setState(() => _restartingNginx = false);
      _checkPorts();
    }
  }

  Future<void> _startNginxContainer() async {
    final container = _containerNameController.text.trim();
    if (container.isEmpty) return;
    setState(() => _restartingNginx = true);
    try {
      final docker = await PlatformService.dockerPath;
      // Try docker start first (existing container)
      final result =
          await Process.run(docker, ['start', container], runInShell: true);
      if (result.exitCode != 0) {
        // Container doesn't exist - try docker compose up from nginx project dir
        final confDir = _confDirController.text.trim();
        final nginxRoot =
            confDir.endsWith('conf.d') ? p.dirname(confDir) : confDir;
        final composeFile = File(p.join(nginxRoot, 'docker-compose.yml'));
        if (await composeFile.exists()) {
          final composeResult = await Process.run(
            docker,
            ['compose', 'up', '-d'],
            workingDirectory: nginxRoot,
            runInShell: true,
          );
          if (mounted) {
            if (composeResult.exitCode != 0) {
              setState(() =>
                  _nginxError = composeResult.stderr.toString().trim());
            } else {
              setState(() => _nginxError = null);
            }
          }
        } else {
          if (mounted) {
            setState(() => _nginxError = result.stderr.toString().trim());
          }
        }
      } else {
        if (mounted) setState(() => _nginxError = null);
      }
    } catch (e) {
      if (mounted) setState(() => _nginxError = e.toString());
    }
    if (mounted) {
      setState(() => _restartingNginx = false);
      _checkPorts();
    }
  }

  Future<void> _stopNginxContainer() => _dockerCommand('stop');

  Future<void> _restartNginxContainer() => _dockerCommand('restart');

  // ── Kill process ──

  Future<void> _killProcess(
      ({int port, String? process, int? pid, String source}) conflict) async {
    if (conflict.pid == null) return;
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(context.l10n.nginxKillProcess),
          const Spacer(),
          AppDialog.closeButton(ctx,
              onClose: () => Navigator.pop(ctx, false)),
        ]),
        content: Text(context.l10n.nginxKillConfirm(
            conflict.process ?? 'unknown',
            '${conflict.pid}',
            conflict.port)),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(context.l10n.nginxKillProcess)),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await NginxService.killProcess(conflict.pid!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.exitCode == 0
              ? context.l10n.nginxKillSuccess(conflict.port)
              : context.l10n.nginxKillFailed(result.stderr)),
          backgroundColor: result.exitCode == 0 ? null : Colors.red,
        ),
      );
      _checkPorts();
    }
  }

  // ── Import / Delete ──

  Future<void> _importNginxFolder() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.nginxConfDir);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.nginxConfDir);
    }
    if (path == null) return;

    // Auto-detect: if user picked the nginx root folder, use conf.d inside it
    final confDInside = Directory(p.join(path, 'conf.d'));
    final confDir =
        await confDInside.exists() ? p.join(path, 'conf.d') : path;

    setState(() {
      _confDirController.text = confDir;
      _editingNginx = false;
    });
    await _saveNginxSettings();
    _checkPorts();
  }

  Future<void> _deleteNginxConfig() async {
    bool deleteFolder = false;
    final confDir = _confDirController.text.trim();
    // Derive nginx root (parent of conf.d)
    final nginxRoot =
        confDir.endsWith('conf.d') ? p.dirname(confDir) : confDir;

    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            Text(context.l10n.nginxDeleteTitle),
            const Spacer(),
            AppDialog.closeButton(ctx,
                onClose: () => Navigator.pop(ctx, false)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.nginxDeleteConfirmText),
              const SizedBox(height: AppSpacing.xs),
              Text(confDir,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.sm,
                      color: Colors.grey.shade500)),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Checkbox(
                    value: deleteFolder,
                    onChanged: (v) =>
                        setDialogState(() => deleteFolder = v ?? false),
                  ),
                  Expanded(
                    child: Text(context.l10n.nginxDeleteAlsoFolder,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: Text(context.l10n.delete)),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    if (deleteFolder) {
      try {
        final dir = Directory(nginxRoot);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }

    setState(() {
      _confDirController.clear();
      _domainSuffixController.clear();
      _containerNameController.text = 'nginx';
    });
    await _saveNginxSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nginxDeleted)),
      );
    }
  }

  void _showInitNginxDialog() {
    AppDialog.show(
      context: context,
      builder: (ctx) => NginxInitDialog(
        onCreated: (confDir, domain) {
          _confDirController.text = confDir;
          _domainSuffixController.text = '.$domain';
          _saveNginxSettings();
          setState(() {
            _editingNginx = false;
          });
          _checkPorts();
        },
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    if (!_hasNginxConfig && !_editingNginx) {
      return _buildNginxEmptyState();
    }

    // Auto-check ports when showing info card
    if (_portConflicts == null && !_checkingPorts && !_editingNginx) {
      _checkPorts();
    }

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: _editingNginx ? _buildNginxEditForm() : _buildNginxInfoCard(),
    );
  }

  Widget _buildNginxEmptyState() {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dns_outlined, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: AppSpacing.lg),
            Text(context.l10n.nginxSettings,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(context.l10n.nginxInitSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _showInitNginxDialog,
                  icon: const Icon(Icons.create_new_folder),
                  label: Text(context.l10n.nginxInitCreate),
                ),
                const SizedBox(width: AppSpacing.lg),
                FilledButton.tonalIcon(
                  onPressed: _importNginxFolder,
                  icon: const Icon(Icons.download),
                  label: Text(context.l10n.nginxImport),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNginxInfoCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dns,
                        color: Colors.green, size: AppIconSize.xl),
                    const SizedBox(width: AppSpacing.md),
                    Text(context.l10n.nginxSettings,
                        style: const TextStyle(
                            fontSize: AppFontSize.xl,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_dockerNginxRunning == true)
                      IconButton(
                        onPressed:
                            _restartingNginx ? null : _stopNginxContainer,
                        icon: const Icon(Icons.stop_circle_outlined),
                        color: Colors.orange,
                        tooltip: 'Stop',
                      )
                    else
                      IconButton(
                        onPressed:
                            _restartingNginx ? null : _startNginxContainer,
                        icon: const Icon(Icons.play_circle_outlined),
                        color: Colors.green,
                        tooltip: 'Start',
                      ),
                    IconButton(
                      onPressed:
                          _restartingNginx ? null : _restartNginxContainer,
                      icon: _restartingNginx
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.restart_alt),
                      tooltip: 'Restart',
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _editingNginx = true),
                      icon: const Icon(Icons.edit),
                      tooltip: context.l10n.edit,
                    ),
                    IconButton(
                      onPressed: _deleteNginxConfig,
                      icon: const Icon(Icons.delete),
                      color: Colors.red,
                      tooltip: context.l10n.delete,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _infoRow(
                    context.l10n.nginxConfDir, _confDirController.text),
                const SizedBox(height: AppSpacing.xs),
                _infoRow(context.l10n.nginxDomainSuffix,
                    _domainSuffixController.text),
                const SizedBox(height: AppSpacing.xs),
                _infoRow(context.l10n.nginxContainerName,
                    _containerNameController.text),
                const SizedBox(height: AppSpacing.sm),
                if (_dockerNginxRunning != null)
                  Row(
                    children: [
                      Icon(
                        _dockerNginxRunning!
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 12,
                        color:
                            _dockerNginxRunning! ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _dockerNginxRunning!
                            ? context.l10n.nginxDockerRunning
                            : context.l10n.nginxDockerStopped,
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w600,
                          color: _dockerNginxRunning!
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                if (_nginxError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: AppRadius.smallBorderRadius,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: AppIconSize.md),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _nginxError!,
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: AppFontSize.sm,
                                fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _nginxError = null),
                          icon:
                              const Icon(Icons.close, size: AppIconSize.sm),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Port conflict warning - only show when non-docker process occupies 80/443
        if (_portConflicts != null &&
            _portConflicts!.any((c) => !c.source.startsWith('docker:')))
          ..._portConflicts!
              .where((c) => !c.source.startsWith('docker:'))
              .map((conflict) {
            final isNginxLocal =
                NginxService.isLocalNginx(conflict.process);
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: AppRadius.mediumBorderRadius,
                  border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.orange),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isNginxLocal
                                    ? context.l10n.nginxLocalDetected
                                    : context.l10n.nginxPortInUse(
                                        conflict.port,
                                        conflict.process ?? 'unknown',
                                        '${conflict.pid ?? '?'}'),
                                style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Port ${conflict.port}  •  ${conflict.process ?? 'unknown'}  •  PID: ${conflict.pid ?? '?'}',
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.orange.shade300),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (isNginxLocal) ...[
                      Text(context.l10n.nginxLocalDisableHint,
                          style: TextStyle(
                              fontSize: AppFontSize.sm,
                              color: Colors.orange.shade300)),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: AppRadius.smallBorderRadius,
                        ),
                        child: Text(
                          Platform.isMacOS
                              ? context.l10n.nginxLocalDisableMac
                              : Platform.isWindows
                                  ? context.l10n.nginxLocalDisableWindows
                                  : context.l10n.nginxLocalDisableLinux,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: AppFontSize.sm),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: conflict.pid != null
                            ? () => _killProcess(conflict)
                            : null,
                        icon: const Icon(Icons.stop_circle),
                        label: Text(context.l10n.nginxKillProcess),
                      ),
                    ] else
                      FilledButton.tonalIcon(
                        onPressed: conflict.pid != null
                            ? () => _killProcess(conflict)
                            : null,
                        icon: const Icon(Icons.dangerous),
                        label: Text(context.l10n.nginxKillProcess),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 180,
          child: Text(label,
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: AppFontSize.sm)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: AppFontSize.sm)),
        ),
      ],
    );
  }

  Widget _buildNginxEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.nginxSettings,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _confDirController,
                decoration: InputDecoration(
                  labelText: context.l10n.nginxConfDir,
                  hintText: context.l10n.nginxConfDirHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                readOnly: true,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: _pickConfDir,
              icon: const Icon(Icons.folder_open),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _domainSuffixController,
                decoration: InputDecoration(
                  labelText: context.l10n.nginxDomainSuffix,
                  hintText: context.l10n.nginxDomainSuffixHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: TextField(
                controller: _containerNameController,
                decoration: InputDecoration(
                  labelText: context.l10n.nginxContainerName,
                  hintText: context.l10n.nginxContainerNameHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () async {
                await _saveNginxSettings();
                setState(() => _editingNginx = false);
                _checkPorts();
              },
              icon: const Icon(Icons.save),
              label: Text(context.l10n.save),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: () {
                _loadNginxSettings();
                setState(() => _editingNginx = false);
              },
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}
