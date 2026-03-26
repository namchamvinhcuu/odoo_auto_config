import 'package:flutter/material.dart';
import 'quick_create_screen.dart';
import 'projects_screen.dart';
import 'profile_screen.dart';
import 'python_check_screen.dart';
import 'venv_screen.dart';
import 'vscode_config_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _screens = <Widget>[
    ProjectsScreen(),
    QuickCreateScreen(),
    ProfileScreen(),
    PythonCheckScreen(),
    VenvScreen(),
    VscodeConfigScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.settings_suggest,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Odoo Auto Config',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.folder_special),
                selectedIcon:
                    Icon(Icons.folder_special, color: Colors.blue),
                label: Text('Projects'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rocket_launch),
                selectedIcon:
                    Icon(Icons.rocket_launch, color: Colors.blue),
                label: Text('Quick Create'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person),
                selectedIcon: Icon(Icons.person, color: Colors.blue),
                label: Text('Profiles'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.search),
                selectedIcon: Icon(Icons.search, color: Colors.blue),
                label: Text('Python Check'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.terminal),
                selectedIcon: Icon(Icons.terminal, color: Colors.blue),
                label: Text('Venv Manager'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.code),
                selectedIcon: Icon(Icons.code, color: Colors.blue),
                label: Text('VSCode Config'),
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
