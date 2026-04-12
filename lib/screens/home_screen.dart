import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/generated/version.dart';
import 'package:odoo_auto_config/providers/docker_status_provider.dart';
import 'package:odoo_auto_config/providers/theme_provider.dart';
import 'package:odoo_auto_config/providers/update_provider.dart';
import 'package:odoo_auto_config/services/instance_service.dart';
// TODO: re-enable tray when ready
// import 'package:odoo_auto_config/services/tray_service.dart';
import 'package:odoo_auto_config/services/update_service.dart';
import 'other_projects/other_projects_screen.dart';
import 'environment_screen.dart';
import 'odoo_projects/odoo_projects_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  /// Navigate to Settings tab, optionally to a specific sub-tab
  static void navigateToSettings({int settingsTab = 0}) {
    SettingsScreen.initialTab = settingsTab;
    _HomeScreenState._instance?._goToTab(4);
  }

  /// Re-check Docker status and update banner
  static void recheckDocker() {
    _HomeScreenState._instance?._recheckViaProvider();
  }

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WindowListener {
  static _HomeScreenState? _instance;
  int _selectedIndex = 0;
  final List<int> _backHistory = [];
  final List<int> _forwardHistory = [];
  String? _projectLabel;

  static const _tabLabels = [
    'Odoo Projects',
    'Other Projects',
    'Profiles',
    'Environment',
    'Settings',
  ];

  /// Set the instance label to a specific project name.
  /// Call from dialogs when focusing on a project. Pass null to revert to tab name.
  // ignore: unused_element
  static void setProjectLabel(String? projectName) {
    final state = _instance;
    if (state == null) return;
    state._projectLabel = projectName;
    state._updateInstanceLabel();
  }

  void _updateInstanceLabel() {
    final label = _projectLabel ?? _tabLabels[_selectedIndex];
    InstanceService.updateLabel(label);
  }

  void _goToTab(int index) {
    if (index != _selectedIndex) {
      _backHistory.add(_selectedIndex);
      _forwardHistory.clear();
    }
    setState(() => _selectedIndex = index);
    _projectLabel = null;
    _updateInstanceLabel();
  }

  void _goBack() {
    if (_backHistory.isEmpty) return;
    _forwardHistory.add(_selectedIndex);
    setState(() => _selectedIndex = _backHistory.removeLast());
    _projectLabel = null;
    _updateInstanceLabel();
  }

  void _goForward() {
    if (_forwardHistory.isEmpty) return;
    _backHistory.add(_selectedIndex);
    setState(() => _selectedIndex = _forwardHistory.removeLast());
    _projectLabel = null;
    _updateInstanceLabel();
  }
  void _recheckViaProvider() {
    ref.read(dockerStatusProvider.notifier).check();
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
    windowManager.addListener(this);
    _updateInstanceLabel();
  }


  static const _manualUrl =
      'https://github.com/namchamvinhcuu/workspace-configuration#readme';

  Future<void> _openUserManual() async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [_manualUrl], runInShell: true);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', _manualUrl], runInShell: true);
      } else {
        await Process.run('xdg-open', [_manualUrl], runInShell: true);
      }
    } catch (_) {}
  }

  Future<void> _checkUpdateWithSnackBar() async {
    final info = await UpdateService.checkForUpdate();
    if (info != null && info.hasUpdate) {
      // Provider will pick it up via its own check; but we can also set it
      // No need — provider already has it. Just in case it missed:
      ref.read(updateProvider.notifier).checkForUpdate();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('v$appVersion — up to date')),
      );
    }
  }

  Future<void> _performUpdate() async {
    final success = await ref.read(updateProvider.notifier).performUpdate();
    if (!success && mounted) {
      final updateState = ref.read(updateProvider);
      final message = updateState.info?.downloadUrl == null
          ? context.l10n.updateDownloadFailed
          : context.l10n.updateInstallFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    if (_instance == this) _instance = null;
    super.dispose();
  }


  @override
  void onWindowClose() async {
    // TODO: re-enable minimize to tray when ready
    // await TrayService.hideToTray();
    await InstanceService.cleanup();
    exit(0);
  }

  static const _screens = <Widget>[
    OdooProjectsScreen(),
    OtherProjectsScreen(),
    ProfileScreen(),
    EnvironmentScreen(),
    SettingsScreen(),
  ];

  bool _resizing = false;

  Future<void> _setWindowSize(WindowSize ws) async {
    final currentWs = ref.read(themeProvider).windowSize;
    if (_resizing || ws == currentWs) return;
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

    _resizing = false;
    ref.read(themeProvider.notifier).setWindowSize(ws);
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
    final dockerStatus = ref.watch(dockerStatusProvider);
    final updateState = ref.watch(updateProvider);

    final dockerBanner = dockerStatus.installed == false
        ? context.l10n.dockerNotInstalledBanner
        : (dockerStatus.installed == true && dockerStatus.running == false)
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
          if (updateState.hasUpdate)
            MaterialBanner(
              content: Text(
                context.l10n.updateAvailable(
                    updateState.info!.currentVersion, updateState.info!.latestVersion),
              ),
              leading: const Icon(Icons.system_update, color: Colors.blue),
              backgroundColor: Colors.blue.withValues(alpha: 0.1),
              actions: [
                if (updateState.updating)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: AppIconSize.md,
                      height: AppIconSize.md,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _performUpdate,
                    child: Text(context.l10n.updateNow),
                  ),
                TextButton(
                  onPressed: () => ref.read(updateProvider.notifier).dismiss(),
                  child: Text(context.l10n.dismiss),
                ),
              ],
            ),
          if (dockerBanner != null)
            MaterialBanner(
              content: Text(dockerBanner),
              leading: Icon(Icons.sailing,
                  color: dockerStatus.installed == false
                      ? Colors.red
                      : Colors.orange),
              backgroundColor: dockerStatus.installed == false
                  ? Colors.red.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              actions: [
                TextButton(
                  onPressed: () => _goToTab(3),
                  child: Text(context.l10n.dockerGoToSettings),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(dockerStatusProvider.notifier).dismiss(),
                  child: Text(context.l10n.dismiss),
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
                    selected: {ref.watch(themeProvider).windowSize},
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // TODO: re-enable back/forward buttons if needed
                      // Row(
                      //   mainAxisSize: MainAxisSize.min,
                      //   children: [
                      //     IconButton(
                      //       onPressed: _backHistory.isNotEmpty ? _goBack : null,
                      //       icon: const Icon(Icons.arrow_back),
                      //       tooltip: _backHistory.isNotEmpty ? context.l10n.back : null,
                      //       iconSize: AppIconSize.lg,
                      //     ),
                      //     IconButton(
                      //       onPressed: _forwardHistory.isNotEmpty ? _goForward : null,
                      //       icon: const Icon(Icons.arrow_forward),
                      //       tooltip: _forwardHistory.isNotEmpty ? context.l10n.forward : null,
                      //       iconSize: AppIconSize.lg,
                      //     ),
                      //   ],
                      // ),
                      // const SizedBox(height: AppSpacing.sm),
                      IconButton(
                        onPressed: () => InstanceService.launchNewInstance(),
                        icon: const Icon(Icons.open_in_new),
                        tooltip: context.l10n.newWindow,
                        iconSize: AppIconSize.lg,
                      ),
                      SizedBox(
                        width: AppNav.minExtendedWidth - AppSpacing.xxl * 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Container(height: 1, color: Colors.grey.shade500),
                        ),
                      ),
                      Text(
                        'v$appVersion',
                        style: TextStyle(
                          fontSize: AppFontSize.xs,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: updateState.updating
                            ? null
                            : () => _checkUpdateWithSnackBar(),
                        icon: const Icon(Icons.system_update,
                            size: AppIconSize.lg),
                        label: const Text('Check Update'),
                      ),
                      TextButton.icon(
                        onPressed: _openUserManual,
                        icon: const Icon(Icons.menu_book,
                            size: AppIconSize.lg),
                        label: Text(context.l10n.userManual),
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
