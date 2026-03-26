import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import 'projects_screen.dart';
import 'profile_screen.dart';
import 'python_check_screen.dart';
import 'venv_screen.dart';
import 'vscode_config_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    ProjectsScreen(),
    ProfileScreen(),
    PythonCheckScreen(),
    VenvScreen(),
    VscodeConfigScreen(),
    SettingsScreen(),
  ];

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
                ],
              ),
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.folder_special),
                selectedIcon:
                    const Icon(Icons.folder_special, color: Colors.blue),
                label: Text(context.l10n.navProjects),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.person),
                selectedIcon: const Icon(Icons.person, color: Colors.blue),
                label: Text(context.l10n.navProfiles),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search),
                selectedIcon: const Icon(Icons.search, color: Colors.blue),
                label: Text(context.l10n.navPythonCheck),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.terminal),
                selectedIcon: const Icon(Icons.terminal, color: Colors.blue),
                label: Text(context.l10n.navVenvManager),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.code),
                selectedIcon: const Icon(Icons.code, color: Colors.blue),
                label: Text(context.l10n.navVscodeConfig),
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
