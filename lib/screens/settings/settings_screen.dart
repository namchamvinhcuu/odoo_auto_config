import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'docker_tab.dart';
import 'git_tab.dart';
import 'nginx_tab.dart';
import 'postgres_tab.dart';
import 'python_tab.dart';
import 'shortcuts_tab.dart';
import 'theme_tab.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  /// Set by HomeScreen to switch to a specific tab on navigate
  static int initialTab = 0;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 7,
      vsync: this,
      initialIndex: SettingsScreen.initialTab,
    );
    SettingsScreen.initialTab = 0; // reset after use
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.palette), text: context.l10n.themeMode),
            const Tab(icon: Icon(Icons.sailing), text: 'Docker'),
            const Tab(icon: Icon(Icons.code), text: 'Python'),
            const Tab(icon: Icon(Icons.storage), text: 'PostgreSQL'),
            const Tab(icon: Icon(Icons.dns), text: 'Nginx'),
            const Tab(icon: Icon(Icons.key), text: 'Git'),
            Tab(
              icon: const Icon(Icons.keyboard),
              text: context.l10n.shortcutsTitle,
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              ThemeTab(),
              DockerTab(),
              PythonTab(),
              PostgresTab(),
              NginxTab(),
              GitTab(),
              ShortcutsTab(),
            ],
          ),
        ),
      ],
    );
  }
}
