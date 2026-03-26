import 'package:flutter/material.dart';
import 'storage_service.dart';

class LocaleService extends ChangeNotifier {
  Locale? _locale; // null = system default

  Locale? get locale => _locale;

  static const supportedLocales = [
    Locale('en'),
    Locale('vi'),
    Locale('ko'),
  ];

  static const localeNames = {
    'en': 'English',
    'vi': 'Tiếng Việt',
    'ko': '한국어',
  };

  Future<void> load() async {
    final settings = await StorageService.loadSettings();
    final code = settings['locale'] as String?;
    if (code != null && code.isNotEmpty) {
      _locale = Locale(code);
    }
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    final settings = await StorageService.loadSettings();
    settings['locale'] = locale?.languageCode ?? '';
    await StorageService.saveSettings(settings);
    notifyListeners();
  }
}
