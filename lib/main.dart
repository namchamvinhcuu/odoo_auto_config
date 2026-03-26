import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';

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
  final themeService = ThemeService();
  final localeService = LocaleService();
  await Future.wait([themeService.load(), localeService.load()]);
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
      title: 'Odoo Auto Config',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeService.locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      themeMode: theme.themeMode,
      home: const HomeScreen(),
    );
  }
}
