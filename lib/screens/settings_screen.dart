import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import 'home_screen.dart';
import '../l10n/l10n_extension.dart';
import '../models/python_info.dart';
import '../services/docker_install_service.dart';
import '../services/locale_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/postgres_service.dart';
import '../services/python_checker_service.dart';
import '../services/python_install_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/tray_service.dart';
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
  late final TabController _pythonSubTabController;

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
  bool _startingDocker = false;
  String? _dockerVersion;
  String? _dockerComposeVersion;

  // Git
  List<Map<String, dynamic>> _gitAccounts = [];
  String? _defaultGitAccount; // name of default account
  bool _gitLoaded = false;

  // PostgreSQL
  bool? _pgInstalled;
  String? _pgVersion;
  Map<String, String?>? _pgTools;
  List<PgServerInfo>? _pgServers;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: SettingsScreen.initialTab,
    );
    SettingsScreen.initialTab = 0; // reset after use
    _pythonSubTabController = TabController(length: 2, vsync: this);
    _loadNginxSettings();
    _scanEnvironment();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pythonSubTabController.dispose();
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
      final pgInstalled = await PostgresService.isInstalled();
      final pgVersion =
          pgInstalled ? await PostgresService.getVersion() : null;
      final pgTools = await PostgresService.detectClientTools();
      if (mounted) {
        setState(() {
          _pythonResults = results;
          _dockerInstalled = dInstalled;
          _dockerRunning = dRunning;
          _dockerVersion = dVersion;
          _dockerComposeVersion = dCompose;
          _pgInstalled = pgInstalled;
          _pgVersion = pgVersion;
          _pgTools = pgTools;
          _pythonLoading = false;
        });
        // Update banner in HomeScreen
        HomeScreen.recheckDocker();
      }
      // Server detection runs separately - don't block main scan
      _scanPgServers();
    } catch (_) {
      if (mounted) setState(() => _pythonLoading = false);
    }
  }

  Future<void> _scanPgServers() async {
    if (mounted) setState(() => _pgServers = null); // show loading
    try {
      final servers = await PostgresService.detectServers();
      if (mounted) setState(() => _pgServers = servers);
    } catch (_) {
      if (mounted) setState(() => _pgServers = []);
    }
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

    final info = await _pythonChecker.checkPython(path);
    if (!mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPythonInvalid)),
      );
      return;
    }

    final isDuplicate = _pythonResults?.any(
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

    setState(() {
      _pythonResults = [...?_pythonResults, info];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.importPythonSuccess(info.version))),
    );
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
          setState(() {
            _editingNginx = false;
          });
          _checkPorts();
        },
      ),
    );
  }

  Future<void> _startDockerDesktop() async {
    setState(() => _startingDocker = true);
    try {
      await DockerInstallService.startDaemon();
      // Wait for daemon to become ready (retry up to 30s)
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await DockerInstallService.isRunning()) break;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _startingDocker = false);
      _scanEnvironment();
    }
  }

  void _showDockerInstallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
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
            Tab(icon: const Icon(Icons.sailing), text: 'Docker'),
            Tab(icon: const Icon(Icons.code), text: 'Python'),
            Tab(icon: const Icon(Icons.storage), text: 'PostgreSQL'),
            Tab(icon: const Icon(Icons.dns), text: 'Nginx'),
            Tab(icon: const Icon(Icons.key), text: 'Git'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildThemeTab(),
              _buildDockerTab(),
              _buildPythonTab(),
              _buildPostgresTab(),
              _buildNginxTab(),
              _buildGitTab(),
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

          // Close behavior (chỉ macOS)
          if (TrayService.supported) ...[
            Text(context.l10n.closeBehavior,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            FutureBuilder<String>(
              future: TrayService.getCloseBehavior(),
              builder: (context, snapshot) {
                final value = snapshot.data ?? 'exit';
                return SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'exit',
                      icon: const Icon(Icons.close),
                      label: Text(context.l10n.closeBehaviorExit),
                    ),
                    ButtonSegment(
                      value: 'tray',
                      icon: const Icon(Icons.hide_source),
                      label: Text(context.l10n.closeBehaviorTray),
                    ),
                  ],
                  selected: {value},
                  onSelectionChanged: (v) {
                    TrayService.setCloseBehavior(v.first);
                    HomeScreen.updateCloseBehavior(v.first);
                    setState(() {});
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxxl),
          ],

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
        TabBar(
          controller: _pythonSubTabController,
          tabs: [
            Tab(icon: const Icon(Icons.code), text: context.l10n.pythonCheckTitle),
            Tab(icon: const Icon(Icons.terminal), text: 'Venv'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _pythonSubTabController,
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
                onPressed: _pythonLoading ? null : _importPython,
                icon: const Icon(Icons.folder_open),
                label: Text(context.l10n.importPython),
              ),
              const SizedBox(width: AppSpacing.sm),
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
          const SizedBox(height: AppSpacing.lg),
          if (_pythonLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_pythonResults != null && _pythonResults!.isEmpty)
            StatusCard(
              title: context.l10n.noPythonFound,
              subtitle: context.l10n.noPythonFoundSubtitle,
              status: StatusType.warning,
            )
          else if (_pythonResults != null)
            ...(_pythonResults!.map((info) {
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
                        onPressed: () => _showPythonUninstallDialog(info),
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


  void _showPythonUninstallDialog(PythonInfo info) {
    // Extract major.minor from version string (e.g. "3.11.9" -> "3.11")
    final parts = info.version.split('.');
    final majorMinor = parts.length >= 2 ? '${parts[0]}.${parts[1]}' : info.version;

    showDialog(
      context: context,
      builder: (ctx) => _PythonUninstallDialog(
        version: majorMinor,
        fullVersion: info.version,
        executablePath: info.executablePath,
        onUninstalled: () => _scanEnvironment(),
      ),
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

  Future<void> _startNginxContainer() async {
    final container = _containerNameController.text.trim();
    if (container.isEmpty) return;
    setState(() => _restartingNginx = true);
    try {
      final docker = await PlatformService.dockerPath;
      // Try docker start first (existing container)
      final result = await Process.run(docker, ['start', container],
          runInShell: true);
      if (result.exitCode != 0) {
        // Container doesn't exist — try docker compose up from nginx project dir
        final confDir = _confDirController.text.trim();
        final nginxRoot = confDir.endsWith('conf.d')
            ? p.dirname(confDir)
            : confDir;
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
              setState(() => _nginxError = composeResult.stderr.toString().trim());
            } else {
              setState(() => _nginxError = null);
            }
          }
        } else {
          if (mounted) setState(() => _nginxError = result.stderr.toString().trim());
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
    final confDInside = Directory(p.join(path, 'conf.d'));
    final confDir = await confDInside.exists() ? p.join(path, 'conf.d') : path;

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
    final nginxRoot = confDir.endsWith('conf.d')
        ? p.dirname(confDir)
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
                      if (_dockerRunning != true) ...[
                        const SizedBox(width: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed: _startingDocker ? null : _startDockerDesktop,
                          icon: _startingDocker
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.play_arrow),
                          label: Text(_startingDocker
                              ? context.l10n.starting
                              : context.l10n.startDockerDesktop),
                        ),
                      ],
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

  // ── Tab: PostgreSQL ──

  void _showPostgresInstallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PostgresInstallDialog(
        onInstalled: () => _scanEnvironment(),
      ),
    );
  }

  void _showPgSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PgSetupDialog(
        onCreated: () {
          _scanEnvironment();
        },
      ),
    );
  }

  bool _pgActionLoading = false;

  Future<void> _pgContainerAction(
      String container, Future<bool> Function(String) action) async {
    if (_pgActionLoading) return;
    setState(() => _pgActionLoading = true);
    await action(container);
    await _scanPgServers();
    if (mounted) setState(() => _pgActionLoading = false);
  }

  Future<void> _pgLocalStartAction() async {
    if (_pgActionLoading) return;
    setState(() => _pgActionLoading = true);
    await PostgresService.startLocalService();
    await _scanPgServers();
    if (mounted) setState(() => _pgActionLoading = false);
  }

  Widget _buildServerCard(PgServerInfo server) {
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
                  onPressed: _pgActionLoading
                      ? null
                      : () => _pgContainerAction(
                            server.containerName!,
                            PostgresService.stopContainer,
                          ),
                  icon: const Icon(Icons.stop),
                  tooltip: 'Stop',
                  color: Colors.red,
                ),
                IconButton(
                  onPressed: _pgActionLoading
                      ? null
                      : () => _pgContainerAction(
                            server.containerName!,
                            PostgresService.restartContainer,
                          ),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Restart',
                ),
              ] else
                IconButton(
                  onPressed: _pgActionLoading
                      ? null
                      : () => _pgContainerAction(
                            server.containerName!,
                            PostgresService.startContainer,
                          ),
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Start',
                  color: Colors.green,
                ),
            ] else if (!isDocker && !server.isReady)
              IconButton(
                onPressed: _pgActionLoading ? null : _pgLocalStartAction,
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Start',
                color: Colors.green,
              ),
            if (_pgActionLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostgresTab() {
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
                onPressed: _pythonLoading ? null : _scanEnvironment,
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
          if (_pgInstalled == null)
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
                        color: _pgInstalled == true
                            ? Colors.blue
                            : Colors.grey,
                        size: AppIconSize.xxl),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PostgreSQL Client',
                              style: const TextStyle(
                                  fontSize: AppFontSize.xl,
                                  fontWeight: FontWeight.bold)),
                          if (_pgVersion != null)
                            Text(_pgVersion!,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    if (_pgInstalled == true) ...[
                      _envChip(context.l10n.postgresInstalled, true),
                    ] else ...[
                      _envChip(context.l10n.postgresNotInstalled, false),
                      const SizedBox(width: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: _showPostgresInstallDialog,
                        icon: const Icon(Icons.download),
                        label: Text(context.l10n.postgresInstall),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Client tools detail
            if (_pgTools != null) ...[
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
                      final path = _pgTools![name];
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
                              size: 18,
                              color: available
                                  ? Colors.green
                                  : Colors.red,
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
              if (_pgInstalled != true) ...[
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: FilledButton.icon(
                    onPressed: _showPostgresInstallDialog,
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
            if (_pgServers == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_pgServers!.isEmpty)
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
                        onPressed: () => _showPgSetupDialog(),
                        icon: const Icon(Icons.add),
                        label: Text(context.l10n.postgresSetupDocker),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(_pgServers!.map((server) => Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _buildServerCard(server),
                  ))),
          ],
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

  // ── Git Tab ──

  Future<void> _loadGitSettings() async {
    if (_gitLoaded) return;
    final settings = await StorageService.loadSettings();
    final accounts = (settings['gitAccounts'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final defaultName = (settings['defaultGitAccount'] ?? '').toString();
    _gitLoaded = true;
    if (mounted) {
      setState(() {
        _gitAccounts = accounts;
        _defaultGitAccount = defaultName.isEmpty ? null : defaultName;
      });
    }
  }

  Future<void> _saveGitAccounts() async {
    final settings = await StorageService.loadSettings();
    settings['gitAccounts'] = _gitAccounts;
    settings['defaultGitAccount'] = _defaultGitAccount ?? '';
    // Giữ tương thích: lưu token của default account vào gitToken
    final def = _gitAccounts.where((a) => a['name'] == _defaultGitAccount).firstOrNull;
    settings['gitToken'] = def?['token'] ?? '';
    await StorageService.saveSettings(settings);
  }

  void _addGitAccount() {
    showDialog(
      context: context,
      builder: (ctx) => _GitAccountDialog(),
    ).then((result) {
      if (result == null) return;
      final account = result as Map<String, dynamic>;
      setState(() {
        _gitAccounts.add(account);
        if (_gitAccounts.length == 1) _defaultGitAccount = account['name'];
      });
      _saveGitAccounts();
    });
  }

  void _editGitAccount(int index) {
    showDialog(
      context: context,
      builder: (ctx) => _GitAccountDialog(existing: _gitAccounts[index]),
    ).then((result) {
      if (result == null) return;
      final account = result as Map<String, dynamic>;
      final oldName = _gitAccounts[index]['name'];
      setState(() {
        _gitAccounts[index] = account;
        if (_defaultGitAccount == oldName) {
          _defaultGitAccount = account['name'];
        }
      });
      _saveGitAccounts();
    });
  }

  void _deleteGitAccount(int index) {
    final name = _gitAccounts[index]['name'];
    setState(() {
      _gitAccounts.removeAt(index);
      if (_defaultGitAccount == name) {
        _defaultGitAccount = _gitAccounts.isNotEmpty ? _gitAccounts.first['name'] : null;
      }
    });
    _saveGitAccounts();
  }

  void _setDefaultGitAccount(String name) {
    setState(() => _defaultGitAccount = name);
    _saveGitAccounts();
  }

  Widget _buildGitTab() {
    _loadGitSettings();
    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.gitSettingsTitle,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(context.l10n.gitSettingsDescription,
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: AppFontSize.md)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _addGitAccount,
                icon: const Icon(Icons.add),
                label: const Text('Add Account'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_gitAccounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  'No Git accounts configured',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ...List.generate(_gitAccounts.length, (i) {
              final account = _gitAccounts[i];
              final name = account['name'] ?? '';
              final username = account['username'] ?? '';
              final email = account['email'] ?? '';
              final isDefault = _defaultGitAccount == name;
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                color: isDefault
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isDefault
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (isDefault) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Chip(
                          label: const Text('Default'),
                          labelStyle: TextStyle(fontSize: AppFontSize.sm),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '$username • $email',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.sm,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isDefault)
                        IconButton(
                          onPressed: () => _setDefaultGitAccount(name),
                          icon: const Icon(Icons.star_border),
                          tooltip: 'Set as default',
                        ),
                      IconButton(
                        onPressed: () => _editGitAccount(i),
                        icon: const Icon(Icons.edit),
                        tooltip: context.l10n.edit,
                      ),
                      IconButton(
                        onPressed: () => _deleteGitAccount(i),
                        icon: const Icon(Icons.delete),
                        color: Colors.red,
                        tooltip: context.l10n.removeFromList,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Git Account Dialog ──

class _GitAccountDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _GitAccountDialog({this.existing});

  @override
  State<_GitAccountDialog> createState() => _GitAccountDialogState();
}

class _GitAccountDialogState extends State<_GitAccountDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _tokenController;
  bool _tokenObscured = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: (e?['name'] ?? '').toString());
    _usernameController = TextEditingController(text: (e?['username'] ?? '').toString());
    _emailController = TextEditingController(text: (e?['email'] ?? '').toString());
    _tokenController = TextEditingController(text: (e?['token'] ?? '').toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _tokenController.text.trim().isNotEmpty;

  void _save() {
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'username': _usernameController.text.trim(),
      'email': _emailController.text.trim(),
      'token': _tokenController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Edit Account' : 'Add Git Account'),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name *',
                hintText: 'e.g. namchamvinhcuu',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'GitHub username',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'user@example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _tokenController,
              obscureText: _tokenObscured,
              decoration: InputDecoration(
                labelText: 'Token *',
                hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _tokenObscured ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _tokenObscured = !_tokenObscured),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(context.l10n.save),
        ),
      ],
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

// ── Python Uninstall Dialog ──

class _PythonUninstallDialog extends StatefulWidget {
  final String version;
  final String fullVersion;
  final String executablePath;
  final VoidCallback onUninstalled;

  const _PythonUninstallDialog({
    required this.version,
    required this.fullVersion,
    required this.executablePath,
    required this.onUninstalled,
  });

  @override
  State<_PythonUninstallDialog> createState() =>
      _PythonUninstallDialogState();
}

class _PythonUninstallDialogState extends State<_PythonUninstallDialog> {
  bool _uninstalling = false;
  bool _uninstalled = false;
  final List<String> _logLines = [];

  Future<void> _uninstall() async {
    setState(() {
      _uninstalling = true;
      _logLines.clear();
    });
    final exitCode = await PythonInstallService.uninstall(
      widget.version,
      (line) {
        if (mounted) setState(() => _logLines.add(line));
      },
    );
    if (mounted) {
      setState(() {
        _uninstalling = false;
        _uninstalled = exitCode == 0;
      });
      if (exitCode == 0) widget.onUninstalled();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.uninstallPython),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_uninstalling && !_uninstalled) ...[
              Text(
                context.l10n.uninstallPythonConfirm(widget.fullVersion),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.executablePath,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.sm,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LogOutput(lines: _logLines, height: 200),
            ],
          ],
        ),
      ),
      actions: [
        if (!_uninstalled)
          TextButton(
            onPressed: _uninstalling ? null : () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        if (_uninstalled)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text(context.l10n.close),
          )
        else
          FilledButton.icon(
            onPressed: _uninstalling ? null : _uninstall,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            icon: _uninstalling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete),
            label: Text(
              _uninstalling
                  ? context.l10n.uninstalling
                  : context.l10n.uninstallPython,
            ),
          ),
      ],
    );
  }
}

// ── PostgreSQL Setup Dialog ──

class _PgSetupDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const _PgSetupDialog({required this.onCreated});

  @override
  State<_PgSetupDialog> createState() => _PgSetupDialogState();
}

class _PgSetupDialogState extends State<_PgSetupDialog> {
  final _userController =
      TextEditingController(text: PostgresService.defaultUser);
  final _passwordController = TextEditingController();
  final _portController =
      TextEditingController(text: PostgresService.defaultPort.toString());

  String _baseDir = '';
  bool _creating = false;
  bool _created = false;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _passwordController.text = PostgresService.defaultPassword;
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _pickBaseDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
          dialogTitle: context.l10n.postgresSetupBaseDir);
    } else {
      path = await FilePicker.platform
          .getDirectoryPath(dialogTitle: context.l10n.postgresSetupBaseDir);
    }
    if (path != null) setState(() => _baseDir = path!);
  }

  bool get _isValid =>
      _baseDir.isNotEmpty &&
      _userController.text.trim().isNotEmpty &&
      _passwordController.text.trim().isNotEmpty &&
      _portController.text.trim().isNotEmpty;

  Future<void> _create() async {
    if (!_isValid) return;
    setState(() {
      _creating = true;
      _logLines.clear();
    });

    try {
      final projectDir = await PostgresService.initProject(
        baseDir: _baseDir,
        dbUser: _userController.text.trim(),
        dbPassword: _passwordController.text.trim(),
        hostPort: int.tryParse(_portController.text.trim()) ??
            PostgresService.defaultPort,
        onOutput: (line) {
          if (mounted) setState(() => _logLines.add(line));
        },
      );

      if (mounted) {
        setState(() {
          _creating = false;
          _created = true;
        });
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.l10n.postgresSetupSuccess(projectDir))),
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
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.postgresSetupTitle),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.postgresSetupSubtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: AppSpacing.lg),
              // Base directory
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _baseDir),
                      decoration: InputDecoration(
                        labelText: context.l10n.postgresSetupBaseDir,
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
              // User + Password
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userController,
                      decoration: InputDecoration(
                        labelText: context.l10n.postgresSetupUser,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: context.l10n.postgresSetupPassword,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Port
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _portController,
                  decoration: InputDecoration(
                    labelText: context.l10n.postgresSetupPort,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_created)
          TextButton(
              onPressed: _creating ? null : () => Navigator.pop(context),
              child: Text(context.l10n.close)),
        if (!_created)
          FilledButton.icon(
            onPressed: (_creating || !_isValid) ? null : _create,
            icon: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.rocket_launch),
            label: Text(_creating
                ? context.l10n.creating
                : context.l10n.postgresSetupDocker),
          ),
        if (_created)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text(context.l10n.close),
          ),
      ],
    );
  }
}

// ── PostgreSQL Install Dialog ──

class _PostgresInstallDialog extends StatefulWidget {
  final VoidCallback onInstalled;
  const _PostgresInstallDialog({required this.onInstalled});

  @override
  State<_PostgresInstallDialog> createState() => _PostgresInstallDialogState();
}

class _PostgresInstallDialogState extends State<_PostgresInstallDialog> {
  bool _installing = false;
  bool _installed = false;
  bool? _pmAvailable;
  String? _installDescription;
  int? _selectedVersion;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _selectedVersion = PlatformService.isWindows ? PostgresService.availableVersions.first : null;
    _init();
  }

  Future<void> _init() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    final cmd = await PostgresService.installCommand(version: _selectedVersion);
    if (mounted) {
      setState(() {
        _pmAvailable = ok;
        _installDescription = cmd.description;
      });
    }
  }

  Future<void> _updateDescription() async {
    final cmd = await PostgresService.installCommand(version: _selectedVersion);
    if (mounted) setState(() => _installDescription = cmd.description);
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    final exitCode = await PostgresService.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    }, version: _selectedVersion);
    if (mounted) {
      setState(() {
        _installing = false;
        _installed = exitCode == 0;
      });
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
      title: Text(context.l10n.postgresInstallTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.postgresInstallSubtitle,
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
              if (PlatformService.isWindows) ...[
                Text(context.l10n.selectVersion,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: PostgresService.availableVersions.map((v) {
                    return ChoiceChip(
                      label: Text('PostgreSQL $v'),
                      selected: _selectedVersion == v,
                      onSelected: _installing
                          ? null
                          : (sel) {
                              setState(() => _selectedVersion = sel ? v : null);
                              _updateDescription();
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_installDescription != null)
                Text(_installDescription!,
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
        if (!_installed)
          TextButton(
              onPressed: _installing ? null : () => Navigator.pop(context),
              child: Text(context.l10n.close)),
        if (_pmAvailable == true)
          _installed
              ? FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check),
                  label: Text(context.l10n.close),
                )
              : FilledButton.icon(
                  onPressed: _installing ? null : _install,
                  icon: _installing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(_installing
                      ? context.l10n.installing
                      : context.l10n.postgresInstall),
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
          final settings = await StorageService.loadSettings();
          settings['dockerRuntime'] = _macOsDocker;
          await StorageService.saveSettings(settings);
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
        TextButton(
            onPressed: _installing ? null : () => Navigator.pop(context),
            child: Text(context.l10n.close)),
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
  bool _created = false;
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
        setState(() {
          _creating = false;
          _created = true;
        });
        final confDir = p.join(projectDir, 'conf.d');
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
                      onChanged: (_) => setState(() {}),
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
                      onChanged: (_) => setState(() {}),
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
        if (!_created)
          TextButton(
              onPressed: _creating ? null : () => Navigator.pop(context),
              child: Text(context.l10n.close)),
        if (_mkcertAvailable == true && !_created)
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
        if (_created)
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: Text(context.l10n.close),
          ),
      ],
    );
  }
}
