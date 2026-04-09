import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

enum WindowSize {
  small(Size(800, 600)),
  medium(Size(1100, 750)),
  large(Size(1400, 900));

  final Size size;
  const WindowSize(this.size);
}

class ThemeState {
  final ThemeMode themeMode;
  final Color seedColor;
  final WindowSize windowSize;

  const ThemeState({
    this.themeMode = ThemeMode.system,
    this.seedColor = const Color(0xFF714B67),
    this.windowSize = WindowSize.large,
  });

  ThemeState copyWith({
    ThemeMode? themeMode,
    Color? seedColor,
    WindowSize? windowSize,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      windowSize: windowSize ?? this.windowSize,
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
    final savedSize = settings['windowSize'] as String?;

    state = ThemeState(
      themeMode: mode != null
          ? ThemeMode.values.firstWhere(
              (m) => m.name == mode,
              orElse: () => ThemeMode.system,
            )
          : ThemeMode.system,
      seedColor:
          colorValue != null ? Color(colorValue) : const Color(0xFF714B67),
      windowSize: savedSize != null
          ? WindowSize.values.firstWhere(
              (w) => w.name == savedSize,
              orElse: () => WindowSize.large,
            )
          : WindowSize.large,
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

  Future<void> setWindowSize(WindowSize ws) async {
    state = state.copyWith(windowSize: ws);
    await StorageService.updateSettings((settings) {
      settings['windowSize'] = ws.name;
    });
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
