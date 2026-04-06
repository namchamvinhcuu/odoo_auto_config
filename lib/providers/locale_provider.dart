import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

class LocaleNotifier extends Notifier<Locale?> {
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

  @override
  Locale? build() => null;

  Future<void> load() async {
    final settings = await StorageService.loadSettings();
    final code = settings['locale'] as String?;
    if (code != null && code.isNotEmpty) {
      state = Locale(code);
    }
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await StorageService.updateSettings((settings) {
      settings['locale'] = locale?.languageCode ?? '';
    });
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);
