import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/python_info.dart';
import '../services/docker_install_service.dart';
import '../services/python_checker_service.dart';
import '../services/python_install_service.dart';
import '../services/platform_service.dart';
import '../widgets/log_output.dart';
import '../widgets/status_card.dart';

class PythonCheckScreen extends StatefulWidget {
  const PythonCheckScreen({super.key});

  @override
  State<PythonCheckScreen> createState() => _PythonCheckScreenState();
}

class _PythonCheckScreenState extends State<PythonCheckScreen> {
  final _checker = PythonCheckerService();
  List<PythonInfo>? _results;
  bool _loading = false;
  String? _error;

  // Docker state
  bool? _dockerInstalled;
  bool? _dockerRunning;
  String? _dockerVersion;
  String? _dockerComposeVersion;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _checker.detectAll();
      await _checkDocker();
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _checkDocker() async {
    final installed = await DockerInstallService.isInstalled();
    final running = installed ? await DockerInstallService.isRunning() : false;
    final version = installed ? await DockerInstallService.getVersion() : null;
    final compose =
        installed ? await DockerInstallService.getComposeVersion() : null;
    if (mounted) {
      setState(() {
        _dockerInstalled = installed;
        _dockerRunning = running;
        _dockerVersion = version;
        _dockerComposeVersion = compose;
      });
    }
  }

  void _showDockerInstallDialog() {
    showDialog(
      context: context,
      builder: (context) => _DockerInstallDialog(onInstalled: () => _scan()),
    );
  }

  Future<void> _importPython() async {
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

    // Validate: check if it's a real Python executable
    final info = await _checker.checkPython(path);
    if (!mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPythonInvalid)),
      );
      return;
    }

    // Check duplicate
    final isDuplicate = _results?.any(
          (r) => r.executablePath == info.executablePath || r.version == info.version,
        ) ??
        false;
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPythonDuplicate)),
      );
      return;
    }

    setState(() {
      _results = [...?_results, info];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.importPythonSuccess(info.version))),
    );
  }

  void _showInstallDialog() {
    showDialog(
      context: context,
      builder: (context) => _PythonInstallDialog(
        installedVersions:
            _results?.map((r) => _majorMinor(r.version)).toSet() ?? {},
        onInstalled: () => _scan(),
      ),
    );
  }

  String _majorMinor(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return version;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              const Icon(Icons.search, size: AppIconSize.xl),
              Text(
                context.l10n.pythonCheckTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: AppSpacing.xxxl),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _importPython,
                icon: const Icon(Icons.folder_open),
                label: Text(context.l10n.importPython),
              ),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _showInstallDialog,
                icon: const Icon(Icons.download),
                label: Text(context.l10n.installPython),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _scan,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.rescan),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.pythonCheckSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: AppSpacing.xxl),

          // ── Docker Status ──
          if (_dockerInstalled != null)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  children: [
                    Icon(
                      Icons.sailing,
                      color: _dockerInstalled == true ? Colors.blue : Colors.grey,
                      size: AppIconSize.xl,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.dockerStatus,
                            style: const TextStyle(
                              fontSize: AppFontSize.lg,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_dockerVersion != null)
                            Text(
                              _dockerVersion!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: AppFontSize.sm,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          if (_dockerComposeVersion != null)
                            Text(
                              _dockerComposeVersion!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: AppFontSize.sm,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_dockerInstalled == true) ...[
                      _buildChip(
                        context.l10n.dockerInstalled,
                        true,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _buildChip(
                        _dockerRunning == true
                            ? context.l10n.dockerRunning
                            : context.l10n.dockerStopped,
                        _dockerRunning == true,
                      ),
                    ] else ...[
                      _buildChip(context.l10n.dockerNotInstalled, false),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: _showDockerInstallDialog,
                        icon: const Icon(Icons.download),
                        label: Text(context.l10n.dockerInstall),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          if (_loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.lg),
                    Text(context.l10n.scanningPython),
                  ],
                ),
              ),
            )
          else if (_error != null)
            StatusCard(
              title: context.l10n.error,
              subtitle: _error!,
              status: StatusType.error,
            )
          else if (_results != null && _results!.isEmpty)
            StatusCard(
              title: context.l10n.noPythonFound,
              subtitle: context.l10n.noPythonFoundSubtitle,
              status: StatusType.warning,
            )
          else if (_results != null)
            Expanded(
              child: ListView.builder(
                itemCount: _results!.length,
                itemBuilder: (context, index) {
                  final info = _results![index];
                  return _buildPythonCard(info);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPythonCard(PythonInfo info) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.code, color: Colors.blue),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  context.l10n.pythonVersion(info.version),
                  style: const TextStyle(
                    fontSize: AppFontSize.xxl,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.pathLabel(info.executablePath),
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _buildChip(
                  context.l10n.pipVersion(info.pipVersion),
                  info.hasPip,
                ),
                const SizedBox(width: AppSpacing.sm),
                _buildChip(
                  context.l10n.venvModule,
                  info.hasVenv,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool available) {
    return Chip(
      avatar: Icon(
        available ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: available ? Colors.green : Colors.red,
      ),
      label: Text(label),
      backgroundColor: available
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
    );
  }
}

class _PythonInstallDialog extends StatefulWidget {
  final Set<String> installedVersions;
  final VoidCallback onInstalled;

  const _PythonInstallDialog({
    required this.installedVersions,
    required this.onInstalled,
  });

  @override
  State<_PythonInstallDialog> createState() => _PythonInstallDialogState();
}

class _PythonInstallDialogState extends State<_PythonInstallDialog> {
  String? _selectedVersion;
  bool _installing = false;
  bool? _pmAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkPackageManager();
  }

  Future<void> _checkPackageManager() async {
    final available = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = available);
  }

  Future<void> _install() async {
    if (_selectedVersion == null) return;
    setState(() {
      _installing = true;
      _logLines.clear();
    });

    final exitCode = await PythonInstallService.install(
      _selectedVersion!,
      (line) {
        if (mounted) setState(() => _logLines.add(line));
      },
    );

    if (mounted) {
      setState(() => _installing = false);
      if (exitCode == 0) {
        widget.onInstalled();
      }
    }
  }

  String _pmNotFoundMessage(BuildContext context) {
    if (PlatformService.isWindows) {
      return context.l10n.packageManagerNotFoundWindows;
    } else if (PlatformService.isMacOS) {
      return context.l10n.packageManagerNotFoundMac;
    }
    return context.l10n.packageManagerNotFoundLinux;
  }

  @override
  Widget build(BuildContext context) {
    final versions = PythonInstallService.availableVersions;

    return AlertDialog(
      title: Text(context.l10n.installPythonTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.installPythonSubtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_pmAvailable == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_pmAvailable == false)
              StatusCard(
                title: context.l10n.packageManagerNotFound,
                subtitle: _pmNotFoundMessage(context),
                status: StatusType.error,
              )
            else ...[
              Text(
                context.l10n.selectVersion,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: versions.map((v) {
                  final installed =
                      widget.installedVersions.contains(v.version);
                  final selected = _selectedVersion == v.version;
                  return ChoiceChip(
                    label: Text(
                      installed ? '${v.label} ✓' : v.label,
                    ),
                    selected: selected,
                    onSelected: (_installing || installed)
                        ? null
                        : (sel) {
                            setState(() {
                              _selectedVersion = sel ? v.version : null;
                            });
                          },
                  );
                }).toList(),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        if (_pmAvailable == true)
          FilledButton.icon(
            onPressed:
                (_installing || _selectedVersion == null) ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(
              _installing ? context.l10n.installing : context.l10n.install,
            ),
          ),
      ],
    );
  }
}

// ── Docker Install Dialog ──

class _DockerInstallDialog extends StatefulWidget {
  final VoidCallback onInstalled;

  const _DockerInstallDialog({required this.onInstalled});

  @override
  State<_DockerInstallDialog> createState() => _DockerInstallDialogState();
}

class _DockerInstallDialogState extends State<_DockerInstallDialog> {
  bool _installing = false;
  bool? _pmAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkPackageManager();
  }

  Future<void> _checkPackageManager() async {
    final available = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = available);
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _logLines.clear();
    });

    final exitCode = await DockerInstallService.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    });

    if (mounted) {
      setState(() => _installing = false);
      if (exitCode == 0) {
        widget.onInstalled();
      }
    }
  }

  String _pmNotFoundMessage(BuildContext context) {
    if (PlatformService.isWindows) {
      return context.l10n.packageManagerNotFoundWindows;
    } else if (PlatformService.isMacOS) {
      return context.l10n.packageManagerNotFoundMac;
    }
    return context.l10n.packageManagerNotFoundLinux;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.dockerInstallTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.dockerInstallSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_pmAvailable == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_pmAvailable == false)
              StatusCard(
                title: context.l10n.packageManagerNotFound,
                subtitle: _pmNotFoundMessage(context),
                status: StatusType.error,
              )
            else ...[
              Text(
                DockerInstallService.installCommand().description,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.sm,
                  color: Colors.grey.shade600,
                ),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        if (_pmAvailable == true)
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(
              _installing ? context.l10n.installing : context.l10n.dockerInstall,
            ),
          ),
      ],
    );
  }
}
