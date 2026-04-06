import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

class ThemeState {
  final ThemeMode themeMode;
  final Color seedColor;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.seedColor = const Color(0xFF714B67),
  });

  ThemeState copyWith({ThemeMode? themeMode, Color? seedColor}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  static const availableColors = <String, Color>{
    'Odoo Purple': Color(0xFF714B67),
    'Blue': Color(0xFF2196F3),
    'Teal': Color(0xFF009688),
    'Green': Color(0xFF4CAF50),
    'Orange': Color(0xFFFF9800),
    'Red': Color(0xFFF44336),
    'Pink': Color(0xFFE91E63),
    'Indigo': Color(0xFF3F51B5),
    'Cyan': Color(0xFF00BCD4),
    'Deep Purple': Color(0xFF673AB7),
    'Amber': Color(0xFFFFC107),
    'Brown': Color(0xFF795548),
  };

  @override
  ThemeState build() => const ThemeState();

  Future<void> load() async {
    final settings = await StorageService.loadSettings();
    final mode = settings['themeMode'] as String?;
    final colorValue = settings['seedColor'] as int?;

    state = ThemeState(
      themeMode: mode != null
          ? ThemeMode.values.firstWhere(
              (m) => m.name == mode,
              orElse: () => ThemeMode.system,
            )
          : ThemeMode.system,
      seedColor: colorValue != null ? Color(colorValue) : const Color(0xFF714B67),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _save();
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color);
    await _save();
  }

  Future<void> _save() async {
    await StorageService.updateSettings((settings) {
      settings['themeMode'] = state.themeMode.name;
      settings['seedColor'] = state.seedColor.toARGB32();
    });
  }
}

final themeProvider =
    NotifierProvider<ThemeNotifier, ThemeState>(ThemeNotifier.new);
