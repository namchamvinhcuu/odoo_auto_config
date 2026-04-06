import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/providers/locale_provider.dart';
import 'package:odoo_auto_config/providers/odoo_projects_provider.dart';
import 'package:odoo_auto_config/providers/theme_provider.dart';
import 'package:odoo_auto_config/screens/home_screen.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'package:odoo_auto_config/services/tray_service.dart';

void main() async {
  // Log uncaught Flutter errors to stderr so we can see crashes
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    stderr.writeln('FlutterError: ${details.exception}');
    stderr.writeln('${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    stderr.writeln('Unhandled error: $error');
    stderr.writeln('$stack');
    return true;
  };

  WidgetsFlutterBinding.ensureInitialized();

  // Window manager setup
  await windowManager.ensureInitialized();
  const minSize = Size(800, 600);

  // Load saved window size (default: large for first launch)
  final settings = await StorageService.loadSettings();
  final savedSize = settings['windowSize'] as String?;
  final windowSize = WindowSize.values.firstWhere(
    (ws) => ws.name == savedSize,
    orElse: () => WindowSize.large,
  );
  await windowManager.setMinimumSize(minSize);
  await windowManager.setSize(windowSize.size);
  await windowManager.center();
  await windowManager.setPreventClose(true);
  await windowManager.show();

  // Pre-load preferences before runApp
  final container = ProviderContainer();
  await Future.wait([
    container.read(themeProvider.notifier).load(),
    container.read(localeProvider.notifier).load(),
    container.read(odooProjectsProvider.future),
  ]);

  // Init system tray
  await TrayService.init(showLabel: 'Show', quitLabel: 'Quit');

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OdooAutoConfigApp(),
    ),
  );
}

class OdooAutoConfigApp extends ConsumerWidget {
  const OdooAutoConfigApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'Workspace Configuration',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: _buildTheme(theme.seedColor, Brightness.light),
      darkTheme: _buildTheme(theme.seedColor, Brightness.dark),
      themeMode: theme.themeMode,
      home: const SelectionArea(child: HomeScreen()),
    );
  }

  static const _buttonCursor = WidgetStatePropertyAll(SystemMouseCursors.click);

  static ThemeData _buildTheme(Color seedColor, Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonCursor),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonCursor),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonCursor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonCursor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonCursor),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(mouseCursor: _buttonCursor),
      ),
    );
  }
}
