import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../services/docker_install_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/storage_service.dart';
import '../generated/version.dart';
import '../services/tray_service.dart';
import '../services/update_service.dart';
import 'workspaces_screen.dart';
import 'environment_screen.dart';
import 'projects_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

enum WindowSize {
  small(Size(800, 600)),
  medium(Size(1100, 750)),
  large(Size(1400, 900));

  final Size size;
  const WindowSize(this.size);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Navigate to Settings tab, optionally to a specific sub-tab
  static void navigateToSettings({int settingsTab = 0}) {
    SettingsScreen.initialTab = settingsTab;
    _HomeScreenState._instance?._goToTab(4);
  }

  /// Re-check Docker status and update banner
  static void recheckDocker() {
    _HomeScreenState._instance?._checkDocker();
  }

  /// Update cached close behavior (gọi từ Settings khi user đổi)
  static void updateCloseBehavior(String value) {
    _HomeScreenState._instance?._closeBehavior = value;
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  static _HomeScreenState? _instance;
  int _selectedIndex = 0;
  final List<int> _backHistory = [];
  final List<int> _forwardHistory = [];
  String _closeBehavior = 'exit';

  void _goToTab(int index) {
    if (index != _selectedIndex) {
      _backHistory.add(_selectedIndex);
      _forwardHistory.clear();
    }
    setState(() => _selectedIndex = index);
  }

  void _goBack() {
    if (_backHistory.isEmpty) return;
    _forwardHistory.add(_selectedIndex);
    setState(() => _selectedIndex = _backHistory.removeLast());
  }

  void _goForward() {
    if (_forwardHistory.isEmpty) return;
    _backHistory.add(_selectedIndex);
    setState(() => _selectedIndex = _forwardHistory.removeLast());
  }
  WindowSize _windowSize = WindowSize.large;

  // Docker status
  bool? _dockerInstalled;
  bool? _dockerRunning;

  // Update status
  UpdateInfo? _updateInfo;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _instance = this;
    windowManager.addListener(this);
    _loadWindowSize();
    _loadCloseBehavior();
    _checkUpdate();
    _checkDocker();
  }

  Future<void> _loadWindowSize() async {
    final settings = await StorageService.loadSettings();
    final saved = settings['windowSize'] as String?;
    if (saved != null && mounted) {
      final ws = WindowSize.values.firstWhere(
        (w) => w.name == saved,
        orElse: () => WindowSize.large,
      );
      setState(() => _windowSize = ws);
    }
  }

  Future<void> _saveWindowSize(WindowSize ws) async {
    final settings = await StorageService.loadSettings();
    settings['windowSize'] = ws.name;
    await StorageService.saveSettings(settings);
  }

  Future<void> _checkDocker() async {
    // Retry up to 3 times with delay - docker daemon may not be ready yet after login
    for (var attempt = 0; attempt < 3; attempt++) {
      final installed = await DockerInstallService.isInstalled();
      final running = installed ? await DockerInstallService.isRunning() : false;

      if (mounted) {
        setState(() {
          _dockerInstalled = installed;
          _dockerRunning = running;
        });
      }

      if (!installed || running) break;

      // Docker installed but daemon not ready - wait and retry
      if (attempt < 2) {
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted) return;
      }
    }

    // Auto-start nginx container if docker is running
    if (_dockerInstalled == true && _dockerRunning == true) {
      await _autoStartNginx();
    }
  }

  Future<void> _checkUpdate({bool showUpToDate = false}) async {
    final info = await UpdateService.checkForUpdate();
    if (info != null && info.hasUpdate && mounted) {
      setState(() => _updateInfo = info);
    } else if (showUpToDate && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('v$appVersion — up to date')),
      );
    }
  }

  Future<void> _performUpdate() async {
    final info = _updateInfo;
    if (info == null || info.downloadUrl == null || info.assetName == null) {
      return;
    }
    setState(() => _updating = true);
    final path = await UpdateService.download(info.downloadUrl!, info.assetName!);
    if (path == null) {
      if (mounted) {
        setState(() => _updating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.updateDownloadFailed)),
        );
      }
      return;
    }
    final installed = await UpdateService.install(path);
    if (!installed && mounted) {
      // Cleanup downloaded file on failure
      try { File(path).deleteSync(); } catch (_) {}
      setState(() => _updating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.updateInstallFailed)),
      );
    }
  }

  Future<void> _autoStartNginx() async {
    final nginx = await NginxService.loadSettings();
    final container = (nginx['containerName'] ?? '').toString();
    if (container.isEmpty) return;

    final running = await NginxService.isDockerContainerRunning(container);
    if (running) return;

    // Container exists but stopped - try to start it
    try {
      final docker = await PlatformService.dockerPath;
      await Process.run(docker, ['start', container], runInShell: true);
    } catch (_) {}
  }

  @override
  @override
  void dispose() {
    windowManager.removeListener(this);
    if (_instance == this) _instance = null;
    super.dispose();
  }

  Future<void> _loadCloseBehavior() async {
    _closeBehavior = await TrayService.getCloseBehavior();
  }

  @override
  void onWindowClose() async {
    // macOS: onWindowClose works normally via setPreventClose
    if (_closeBehavior == 'tray') {
      await TrayService.hideToTray();
    } else {
      await TrayService.destroy();
      await windowManager.destroy();
    }
  }

  @override
  void onWindowEvent(String eventName) {
    // Windows: WM_CLOSE is handled natively (ShowWindow SW_HIDE in flutter_window.cpp),
    // so onWindowClose never fires. Instead, when window is hidden and close behavior
    // is 'exit', we quit the app. The 'hide' event fires for both minimize and close,
    // but minimize also fires 'minimize' event first, so we use the flag to distinguish.
    if (!Platform.isWindows) return;
    if (eventName == 'minimize') {
      _isMinimizing = true;
    } else if (eventName == 'hide') {
      if (_isMinimizing) {
        _isMinimizing = false;
        return;
      }
      // hide from X button (not minimize)
      if (_closeBehavior == 'exit') {
        TrayService.destroy().then((_) => exit(0));
      }
    }
  }

  bool _isMinimizing = false;

  static const _screens = <Widget>[
    ProjectsScreen(),
    WorkspacesScreen(),
    ProfileScreen(),
    EnvironmentScreen(),
    SettingsScreen(),
  ];

  bool _resizing = false;

  Future<void> _setWindowSize(WindowSize ws) async {
    if (_resizing || ws == _windowSize) return;
    _resizing = true;

    final currentSize = await windowManager.getSize();
    final targetSize = ws.size;
    const steps = 12;
    const duration = Duration(milliseconds: 200);
    final stepDuration = Duration(
        microseconds: duration.inMicroseconds ~/ steps);

    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      // Ease-out cubic
      final ease = 1 - (1 - t) * (1 - t) * (1 - t);
      final w = currentSize.width + (targetSize.width - currentSize.width) * ease;
      final h = currentSize.height + (targetSize.height - currentSize.height) * ease;
      await windowManager.setSize(Size(w, h));
      await windowManager.center();
      await Future.delayed(stepDuration);
    }

    setState(() => _windowSize = ws);
    _resizing = false;
    _saveWindowSize(ws);
  }

  String _windowSizeLabel(WindowSize ws) {
    switch (ws) {
      case WindowSize.small:
        return 'S';
      case WindowSize.medium:
        return 'M';
      case WindowSize.large:
        return 'L';
    }
  }

  String _windowSizeTooltip(WindowSize ws) {
    switch (ws) {
      case WindowSize.small:
        return '${context.l10n.wsizeSmall} (800×600)';
      case WindowSize.medium:
        return '${context.l10n.wsizeMedium} (1100×750)';
      case WindowSize.large:
        return '${context.l10n.wsizeLarge} (1400×900)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dockerBanner = _dockerInstalled == false
        ? context.l10n.dockerNotInstalledBanner
        : (_dockerInstalled == true && _dockerRunning == false)
            ? context.l10n.dockerNotRunningBanner
            : null;

    return Listener(
      onPointerDown: (event) {
        // Mouse back button (bit 3 = 8) and forward button (bit 4 = 16)
        if (event.buttons & 0x08 != 0) {
          _goBack();
        } else if (event.buttons & 0x10 != 0) {
          _goForward();
        }
      },
      child: Scaffold(
      body: Column(
        children: [
          if (_updateInfo != null && _updateInfo!.hasUpdate)
            MaterialBanner(
              content: Text(
                context.l10n.updateAvailable(
                    _updateInfo!.currentVersion, _updateInfo!.latestVersion),
              ),
              leading: const Icon(Icons.system_update, color: Colors.blue),
              backgroundColor: Colors.blue.withValues(alpha: 0.1),
              actions: [
                if (_updating)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _performUpdate,
                    child: Text(context.l10n.updateNow),
                  ),
                TextButton(
                  onPressed: () => setState(() => _updateInfo = null),
                  child: Text(context.l10n.dismiss),
                ),
              ],
            ),
          if (dockerBanner != null)
            MaterialBanner(
              content: Text(dockerBanner),
              leading: Icon(Icons.sailing,
                  color: _dockerInstalled == false
                      ? Colors.red
                      : Colors.orange),
              backgroundColor: _dockerInstalled == false
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              actions: [
                TextButton(
                  onPressed: () {
                    // Navigate to Environment screen
                    _goToTab(3);
                  },
                  child: Text(context.l10n.dockerGoToSettings),
                ),
              ],
            ),
          Expanded(
            child: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: AppNav.minExtendedWidth,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => _goToTab(index),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                children: [
                  Icon(
                    Icons.settings_suggest,
                    size: AppIconSize.xxl,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    context.l10n.appTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Window size selector
                  SegmentedButton<WindowSize>(
                    segments: WindowSize.values
                        .map((ws) => ButtonSegment(
                              value: ws,
                              label: Text(_windowSizeLabel(ws),
                                  style: const TextStyle(
                                      fontSize: AppFontSize.sm)),
                              tooltip: _windowSizeTooltip(ws),
                            ))
                        .toList(),
                    selected: {_windowSize},
                    onSelectionChanged: (s) => _setWindowSize(s.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.folder_special),
                selectedIcon:
                    const Icon(Icons.folder_special, color: Colors.blue),
                label: Text(context.l10n.navOdooProjects),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.workspaces),
                selectedIcon:
                    const Icon(Icons.workspaces, color: Colors.blue),
                label: Text(context.l10n.navOtherProjects),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.person),
                selectedIcon: const Icon(Icons.person, color: Colors.blue),
                label: Text(context.l10n.navProfiles),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.checklist),
                selectedIcon:
                    const Icon(Icons.checklist, color: Colors.blue),
                label: Text(context.l10n.envSetupTitle),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings),
                selectedIcon: const Icon(Icons.settings, color: Colors.blue),
                label: Text(context.l10n.navSettings),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _backHistory.isNotEmpty ? _goBack : null,
                            icon: const Icon(Icons.arrow_back),
                            tooltip: _backHistory.isNotEmpty ? context.l10n.back : null,
                            iconSize: AppIconSize.lg,
                          ),
                          IconButton(
                            onPressed: _forwardHistory.isNotEmpty ? _goForward : null,
                            icon: const Icon(Icons.arrow_forward),
                            tooltip: _forwardHistory.isNotEmpty ? context.l10n.forward : null,
                            iconSize: AppIconSize.lg,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton.icon(
                        onPressed: _updating
                            ? null
                            : () => _checkUpdate(showUpToDate: true),
                        icon: const Icon(Icons.system_update,
                            size: AppIconSize.lg),
                        label: const Text('Check Update'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
          ),
        ],
      ),
    ),
    );
  }
}
