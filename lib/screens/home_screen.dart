import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import 'workspaces_screen.dart';
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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  WindowSize _windowSize = WindowSize.medium;

  static const _screens = <Widget>[
    ProjectsScreen(),
    WorkspacesScreen(),
    ProfileScreen(),
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: AppNav.minExtendedWidth,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
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
                icon: const Icon(Icons.settings),
                selectedIcon: const Icon(Icons.settings, color: Colors.blue),
                label: Text(context.l10n.navSettings),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
    );
  }
}
