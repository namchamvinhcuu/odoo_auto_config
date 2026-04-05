import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'storage_service.dart';

class TrayService {
  static final SystemTray _tray = SystemTray();
  static bool _initialized = false;

  /// System tray hỗ trợ macOS và Windows
  /// Linux: tạm tắt (tạo duplicate instance)
  static bool get supported => Platform.isMacOS || Platform.isWindows;

  /// Khởi tạo system tray (macOS + Windows)
  static Future<void> init({
    required String showLabel,
    required String quitLabel,
  }) async {
    if (_initialized || !supported) return;

    final iconPath =
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';

    await _tray.initSystemTray(
      title: '',
      iconPath: iconPath,
      toolTip: 'Workspace Configuration',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: showLabel,
        onClicked: (_) => _showWindow(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: quitLabel,
        onClicked: (_) => _quitApp(),
      ),
    ]);
    await _tray.setContextMenu(menu);

    _tray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventDoubleClick) {
        _showWindow();
      } else if (eventName == kSystemTrayEventRightClick) {
        _tray.popUpContextMenu();
      }
    });

    _initialized = true;
  }

  static Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> _quitApp() async {
    await _tray.destroy();
    exit(0);
  }

  /// Ẩn window vào tray (macOS + Windows)
  /// Windows: không dùng setSkipTaskbar (gây native crash với window_manager 0.5.1)
  /// Window được hide bởi native WM_CLOSE handler trong flutter_window.cpp
  static Future<void> hideToTray() async {
    await windowManager.hide();
  }

  /// Đọc setting close behavior: 'tray' hoặc 'exit'
  /// Linux luôn return 'exit' (chưa hỗ trợ)
  static Future<String> getCloseBehavior() async {
    if (!supported) return 'exit';
    final settings = await StorageService.loadSettings();
    return (settings['closeBehavior'] ?? 'exit').toString();
  }

  /// Lưu setting close behavior
  static Future<void> setCloseBehavior(String value) async {
    final settings = await StorageService.loadSettings();
    settings['closeBehavior'] = value;
    await StorageService.saveSettings(settings);
  }

  static Future<void> destroy() async {
    if (_initialized) {
      await _tray.destroy();
      _initialized = false;
    }
  }
}
