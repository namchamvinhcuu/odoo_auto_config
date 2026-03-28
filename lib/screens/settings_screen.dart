import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/python_info.dart';
import '../services/docker_install_service.dart';
import '../services/locale_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/python_checker_service.dart';
import '../services/python_install_service.dart';
import '../services/theme_service.dart';
import '../widgets/log_output.dart';
import '../widgets/status_card.dart';
import 'venv_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Set by HomeScreen to switch to a specific tab on navigate
  static int initialTab = 0;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  // Nginx
  final _confDirController = TextEditingController();
  final _domainSuffixController = TextEditingController();
  final _containerNameController = TextEditingController();

  // Python + Docker
  final _pythonChecker = PythonCheckerService();
  List<PythonInfo>? _pythonResults;
  bool _pythonLoading = false;
  bool? _dockerInstalled;
  bool? _dockerRunning;
  String? _dockerVersion;
  String? _dockerComposeVersion;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: SettingsScreen.initialTab,
    );
    SettingsScreen.initialTab = 0; // reset after use
    _loadNginxSettings();
    _scanEnvironment();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _confDirController.dispose();
    _domainSuffixController.dispose();
    _containerNameController.dispose();
    super.dispose();
  }

  // ── Nginx ──

  Future<void> _loadNginxSettings() async {
    final nginx = await NginxService.loadSettings();
    _confDirController.text = (nginx['confDir'] ?? '').toString();
    _domainSuffixController.text = (nginx['domainSuffix'] ?? '').toString();
    _containerNameController.text =
        (nginx['containerName'] ?? 'nginx').toString();
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

  // ── Environment ──

  Future<void> _scanEnvironment() async {
    setState(() => _pythonLoading = true);
    try {
      final results = await _pythonChecker.detectAll();
      final dInstalled = await DockerInstallService.isInstalled();
      final dRunning =
          dInstalled ? await DockerInstallService.isRunning() : false;
      final dVersion =
          dInstalled ? await DockerInstallService.getVersion() : null;
      final dCompose =
          dInstalled ? await DockerInstallService.getComposeVersion() : null;
      if (mounted) {
        setState(() {
          _pythonResults = results;
          _dockerInstalled = dInstalled;
          _dockerRunning = dRunning;
          _dockerVersion = dVersion;
          _dockerComposeVersion = dCompose;
          _pythonLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _pythonLoading = false);
    }
  }

  String _majorMinor(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return version;
  }

  void _showPythonInstallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PythonInstallDialog(
        installedVersions:
            _pythonResults?.map((r) => _majorMinor(r.version)).toSet() ?? {},
        onInstalled: () => _scanEnvironment(),
      ),
    );
  }

  void _showInitNginxDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _NginxInitDialog(
        onCreated: (confDir, domain) {
          _confDirController.text = confDir;
          _domainSuffixController.text = '.$domain';
          _saveNginxSettings();
        },
      ),
    );
  }

  void _showDockerInstallDialog() {
    showDialog(
      context: context,
      builder: (ctx) =>
          _DockerInstallDialog(onInstalled: () => _scanEnvironment()),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.palette), text: context.l10n.themeMode),
            Tab(icon: const Icon(Icons.code), text: 'Python'),
            Tab(icon: const Icon(Icons.dns), text: 'Nginx'),
            Tab(icon: const Icon(Icons.sailing), text: 'Docker'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildThemeTab(),
              _buildPythonTab(),
              _buildNginxTab(),
              _buildDockerTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab: Theme ──

  Widget _buildThemeTab() {
    final theme = context.watch<ThemeService>();
    final localeService = context.watch<LocaleService>();

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language
          Text(context.l10n.language,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<Locale?>(
            segments: LocaleService.supportedLocales.map((locale) {
              return ButtonSegment(
                value: locale,
                label: Text(
                    LocaleService.localeNames[locale.languageCode] ?? ''),
              );
            }).toList(),
            selected: {
              localeService.locale ??
                  LocaleService.supportedLocales.firstWhere(
                    (l) =>
                        l.languageCode ==
                        Localizations.localeOf(context).languageCode,
                    orElse: () => const Locale('en'),
                  ),
            },
            onSelectionChanged: (v) => localeService.setLocale(v.first),
          ),
          const SizedBox(height: AppSpacing.xxxl),

          // Theme mode
          Text(context.l10n.themeMode,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto),
                  label: Text(context.l10n.themeSystem)),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode),
                  label: Text(context.l10n.themeLight)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode),
                  label: Text(context.l10n.themeDark)),
            ],
            selected: {theme.themeMode},
            onSelectionChanged: (v) => theme.setThemeMode(v.first),
          ),
          const SizedBox(height: AppSpacing.xxxl),

          // Accent color
          Text(context.l10n.accentColor,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: theme.availableColors.entries.map((entry) {
              final isSelected =
                  entry.value.toARGB32() == theme.seedColor.toARGB32();
              return Tooltip(
                message: entry.key,
                child: InkWell(
                  onTap: () => theme.setSeedColor(entry.value),
                  borderRadius: AppRadius.circularBorderRadius,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color:
                                  Theme.of(context).colorScheme.onSurface,
                              width: 3)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xxxl),

          // Preview
          Text(context.l10n.preview,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                  onPressed: () {}, child: Text(context.l10n.filledButton)),
              FilledButton.tonal(
                  onPressed: () {}, child: Text(context.l10n.tonalButton)),
              OutlinedButton(
                  onPressed: () {}, child: Text(context.l10n.outlined)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tab: Python (+ Venv) ──

  Widget _buildPythonTab() {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, 0),
          child: Row(
            children: [
              Text(context.l10n.pythonCheckTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _pythonLoading ? null : _showPythonInstallDialog,
                icon: const Icon(Icons.download),
                label: Text(context.l10n.installPython),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: _pythonLoading ? null : _scanEnvironment,
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.rescan,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Python list
        if (_pythonLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_pythonResults != null && _pythonResults!.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: StatusCard(
              title: context.l10n.noPythonFound,
              subtitle: context.l10n.noPythonFoundSubtitle,
              status: StatusType.warning,
            ),
          )
        else if (_pythonResults != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              children: _pythonResults!.map((info) {
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
                        _envChip(context.l10n.pipVersion(info.pipVersion),
                            info.hasPip),
                        const SizedBox(width: AppSpacing.sm),
                        _envChip(context.l10n.venvModule, info.hasVenv),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        const Divider(indent: AppSpacing.xxl, endIndent: AppSpacing.xxl),
        // Venv Manager embedded
        const Expanded(child: VenvScreen()),
      ],
    );
  }

  // ── Tab: Nginx ──

  bool get _hasNginxConfig => _confDirController.text.trim().isNotEmpty;
  bool _editingNginx = false;
  List<({int port, String? process, int? pid, String source})>? _portConflicts;
  bool? _dockerNginxRunning;
  bool _checkingPorts = false;
  bool _restartingNginx = false;
  String? _nginxError;

  Future<void> _killProcess(
      ({int port, String? process, int? pid, String source}) conflict) async {
    if (conflict.pid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.nginxKillProcess),
        content: Text(context.l10n.nginxKillConfirm(
            conflict.process ?? 'unknown',
            '${conflict.pid}',
            conflict.port)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
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

  Future<void> _startNginxContainer() => _dockerCommand('start');
  Future<void> _stopNginxContainer() => _dockerCommand('stop');

  Future<void> _restartNginxContainer() => _dockerCommand('restart');

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
    final confDInside = Directory('$path/conf.d');
    final confDir = await confDInside.exists() ? '$path/conf.d' : path;

    setState(() {
      _confDirController.text = confDir;
    });
    await _saveNginxSettings();
  }

  Future<void> _deleteNginxConfig() async {
    bool deleteFolder = false;
    final confDir = _confDirController.text.trim();
    // Derive nginx root (parent of conf.d)
    final nginxRoot = confDir.endsWith('conf.d')
        ? confDir.substring(0, confDir.length - 6)
        : confDir;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.l10n.nginxDeleteTitle),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel)),
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

  Widget _buildNginxTab() {
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
            Icon(Icons.dns_outlined,
                size: 64, color: Colors.grey.shade600),
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
                    const Icon(Icons.dns, color: Colors.green, size: AppIconSize.xl),
                    const SizedBox(width: AppSpacing.md),
                    Text(context.l10n.nginxSettings,
                        style: const TextStyle(
                            fontSize: AppFontSize.xl,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_dockerNginxRunning == true)
                      IconButton(
                        onPressed: _restartingNginx ? null : _stopNginxContainer,
                        icon: const Icon(Icons.stop_circle_outlined),
                        color: Colors.orange,
                        tooltip: 'Stop',
                      )
                    else
                      IconButton(
                        onPressed: _restartingNginx ? null : _startNginxContainer,
                        icon: const Icon(Icons.play_circle_outlined),
                        color: Colors.green,
                        tooltip: 'Start',
                      ),
                    IconButton(
                      onPressed: _restartingNginx ? null : _restartNginxContainer,
                      icon: _restartingNginx
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.restart_alt),
                      tooltip: 'Restart',
                    ),
                    IconButton(
                      onPressed: () => setState(() => _editingNginx = true),
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
                _infoRow(context.l10n.nginxConfDir,
                    _confDirController.text),
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
                        color: _dockerNginxRunning!
                            ? Colors.green
                            : Colors.red,
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
                          icon: const Icon(Icons.close, size: AppIconSize.sm),
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
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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

  // ── Tab: Docker ──

  Widget _buildDockerTab() {
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
                onPressed: _pythonLoading ? null : _scanEnvironment,
                icon: const Icon(Icons.refresh),
                tooltip: context.l10n.rescan,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_dockerInstalled == null)
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
                        color: _dockerInstalled == true
                            ? Colors.blue
                            : Colors.grey,
                        size: AppIconSize.xxl),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Docker',
                              style: const TextStyle(
                                  fontSize: AppFontSize.xl,
                                  fontWeight: FontWeight.bold)),
                          if (_dockerVersion != null)
                            Text(_dockerVersion!,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                          if (_dockerComposeVersion != null)
                            Text(_dockerComposeVersion!,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    if (_dockerInstalled == true) ...[
                      _envChip(context.l10n.dockerInstalled, true),
                      const SizedBox(width: AppSpacing.sm),
                      _envChip(
                        _dockerRunning == true
                            ? context.l10n.dockerRunning
                            : context.l10n.dockerStopped,
                        _dockerRunning == true,
                      ),
                    ] else ...[
                      _envChip(context.l10n.dockerNotInstalled, false),
                      const SizedBox(width: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: _showDockerInstallDialog,
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

// ── Python Install Dialog ──

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
    _checkPM();
  }

  Future<void> _checkPM() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = ok);
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
      title: Text(context.l10n.installPythonTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.installPythonSubtitle,
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
              Text(context.l10n.selectVersion,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children:
                    PythonInstallService.availableVersions.map((v) {
                  final installed =
                      widget.installedVersions.contains(v.version);
                  return ChoiceChip(
                    label: Text(installed ? '${v.label} ✓' : v.label),
                    selected: _selectedVersion == v.version,
                    onSelected: (_installing || installed)
                        ? null
                        : (s) => setState(
                            () => _selectedVersion = s ? v.version : null),
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
            child: Text(context.l10n.close)),
        if (_pmAvailable == true)
          FilledButton.icon(
            onPressed:
                (_installing || _selectedVersion == null) ? null : _install,
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
    _checkPM();
  }

  Future<void> _checkPM() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = ok);
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
      title: Text(context.l10n.dockerInstallTitle),
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
              Text(DockerInstallService.installCommand().description,
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
        TextButton(
            onPressed: _installing ? null : () => Navigator.pop(context),
            child: Text(context.l10n.close)),
        if (_pmAvailable == true)
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
}

// ── Nginx Init Dialog ──

class _NginxInitDialog extends StatefulWidget {
  final void Function(String confDir, String domain) onCreated;
  const _NginxInitDialog({required this.onCreated});

  @override
  State<_NginxInitDialog> createState() => _NginxInitDialogState();
}

class _NginxInitDialogState extends State<_NginxInitDialog> {
  final _folderNameController = TextEditingController(text: 'nginx');
  final _domainController = TextEditingController();
  String _baseDir = '';
  bool _creating = false;
  bool _installingMkcert = false;
  bool? _mkcertAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkMkcert();
  }

  Future<void> _checkMkcert() async {
    final ok = await NginxService.isMkcertAvailable();
    if (mounted) setState(() => _mkcertAvailable = ok);
  }

  Future<void> _installMkcert() async {
    setState(() {
      _installingMkcert = true;
      _logLines.clear();
    });
    final exitCode = await NginxService.installMkcert((line) {
      if (mounted) setState(() => _logLines.add(line));
    });
    if (mounted) {
      setState(() => _installingMkcert = false);
      if (exitCode == 0) {
        await _checkMkcert();
      }
    }
  }

  Future<void> _pickBaseDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.nginxInitBaseDir);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.nginxInitBaseDir);
    }
    if (path != null) setState(() => _baseDir = path!);
  }

  bool get _isValid =>
      _baseDir.isNotEmpty &&
      _folderNameController.text.trim().isNotEmpty &&
      _domainController.text.trim().isNotEmpty;

  Future<void> _create() async {
    if (!_isValid) return;
    setState(() {
      _creating = true;
      _logLines.clear();
    });

    try {
      final projectDir = await NginxService.initProject(
        baseDir: _baseDir,
        folderName: _folderNameController.text.trim(),
        domain: _domainController.text.trim(),
        onOutput: (line) {
          if (mounted) setState(() => _logLines.add(line));
        },
      );

      if (mounted) {
        setState(() => _creating = false);
        final confDir = '$projectDir/conf.d';
        widget.onCreated(confDir, _domainController.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nginxInitSuccess(projectDir))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _logLines.add('[ERROR] $e');
        });
      }
    }
  }

  @override
  void dispose() {
    _folderNameController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.nginxInitTitle),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.nginxInitSubtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: AppSpacing.lg),
            if (_mkcertAvailable == null)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator()))
            else if (_mkcertAvailable == false) ...[
              StatusCard(
                title: context.l10n.nginxInitMkcertRequired,
                subtitle: context.l10n.nginxInitMkcertInstall,
                status: StatusType.error,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _installingMkcert ? null : _installMkcert,
                icon: _installingMkcert
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: Text(_installingMkcert
                    ? context.l10n.installing
                    : 'Install mkcert'),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ]
            else ...[
              // mkcert status
              Card(
                color: Colors.green.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: AppIconSize.md),
                      const SizedBox(width: AppSpacing.sm),
                      Text('mkcert',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade300)),
                      const SizedBox(width: AppSpacing.xs),
                      Text('ready', style: TextStyle(color: Colors.green.shade300)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _baseDir),
                      decoration: InputDecoration(
                        labelText: context.l10n.nginxInitBaseDir,
                        hintText: context.l10n.browseToSelect,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _pickBaseDir,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _folderNameController,
                      decoration: InputDecoration(
                        labelText: context.l10n.nginxInitFolderName,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: TextField(
                      controller: _domainController,
                      decoration: InputDecoration(
                        labelText: context.l10n.nginxInitDomain,
                        hintText: context.l10n.nginxInitDomainHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
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
            onPressed: _creating ? null : () => Navigator.pop(context),
            child: Text(context.l10n.close)),
        if (_mkcertAvailable == true)
          FilledButton.icon(
            onPressed: (_creating || !_isValid) ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.create_new_folder),
            label: Text(_creating
                ? context.l10n.creating
                : context.l10n.nginxInitCreate),
          ),
      ],
    );
  }
}
