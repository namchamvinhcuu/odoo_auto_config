import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/odoo_projects/odoo_projects_screen.dart';
import 'services/locale_service.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'services/tray_service.dart';

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

  final themeService = ThemeService();
  final localeService = LocaleService();
  await Future.wait([
    themeService.load(),
    localeService.load(),
    OdooProjectsScreen.loadViewPreference(),
  ]);

  // Init system tray
  await TrayService.init(showLabel: 'Show', quitLabel: 'Quit');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: localeService),
      ],
      child: const OdooAutoConfigApp(),
    ),
  );
}

class OdooAutoConfigApp extends StatelessWidget {
  const OdooAutoConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    final localeService = context.watch<LocaleService>();

    return MaterialApp(
      title: 'Workspace Configuration',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeService.locale,
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
