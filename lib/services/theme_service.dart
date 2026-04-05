import 'package:flutter/material.dart';
import 'storage_service.dart';

class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _seedColor = const Color(0xFF714B67); // Odoo purple

  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;

  static const _defaultColors = <String, Color>{
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

  Map<String, Color> get availableColors => _defaultColors;

  Future<void> load() async {
    final settings = await StorageService.loadSettings();
    final mode = settings['themeMode'] as String?;
    final colorValue = settings['seedColor'] as int?;

    if (mode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => ThemeMode.system,
      );
    }
    if (colorValue != null) {
      _seedColor = Color(colorValue);
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final settings = await StorageService.loadSettings();
    settings['themeMode'] = _themeMode.name;
    settings['seedColor'] = _seedColor.toARGB32();
    await StorageService.saveSettings(settings);
  }
}
