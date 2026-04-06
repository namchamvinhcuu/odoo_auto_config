import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../home_screen.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/python_info.dart';
import '../../services/docker_install_service.dart';
import '../../services/locale_service.dart';
import '../../services/nginx_service.dart';
import '../../services/platform_service.dart';
import '../../services/postgres_service.dart';
import '../../services/python_checker_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../services/tray_service.dart';
import '../../widgets/status_card.dart';
import '../venv_screen.dart';
import 'docker_install_dialog.dart';
import 'git_account_dialog.dart';
import 'nginx_init_dialog.dart';
import 'pg_setup_dialog.dart';
import 'postgres_install_dialog.dart';
import 'python_install_dialog.dart';
import 'python_uninstall_dialog.dart';

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
    AppDialog.show(
      context: context,
      builder: (ctx) => PythonInstallDialog(
        installedVersions:
            _pythonResults?.map((r) => _majorMinor(r.version)).toSet() ?? {},
        onInstalled: () => _scanEnvironment(),
      ),
    );
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
    AppDialog.show(
      context: context,
      builder: (ctx) =>
          DockerInstallDialog(onInstalled: () => _scanEnvironment()),
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

    AppDialog.show(
      context: context,
      builder: (ctx) => PythonUninstallDialog(
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
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Text(context.l10n.nginxKillProcess),
          const Spacer(),
          AppDialog.closeButton(ctx, onClose: () => Navigator.pop(ctx, false)),
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

    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            Text(context.l10n.nginxDeleteTitle),
            const Spacer(),
            AppDialog.closeButton(ctx, onClose: () => Navigator.pop(ctx, false)),
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
    AppDialog.show(
      context: context,
      builder: (ctx) => PostgresInstallDialog(
        onInstalled: () => _scanEnvironment(),
      ),
    );
  }

  void _showPgSetupDialog() {
    AppDialog.show(
      context: context,
      builder: (ctx) => PgSetupDialog(
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
    AppDialog.show(
      context: context,
      builder: (ctx) => GitAccountDialog(),
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
    AppDialog.show(
      context: context,
      builder: (ctx) => GitAccountDialog(existing: _gitAccounts[index]),
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
