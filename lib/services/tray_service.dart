import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'storage_service.dart';

class TrayService {
  static final SystemTray _tray = SystemTray();
  static bool _initialized = false;

  /// Khởi tạo system tray với icon và menu cơ bản
  static Future<void> init({
    required String showLabel,
    required String quitLabel,
  }) async {
    if (_initialized) return;

    String iconPath;
    if (Platform.isWindows) {
      iconPath = 'assets/tray_icon.png';
    } else {
      iconPath = 'assets/tray_icon.png';
    }

    await _tray.initSystemTray(
      title: 'Workspace Configuration',
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

    // Double-click tray icon → show window
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
    if (!Platform.isMacOS) {
      await windowManager.setSkipTaskbar(false);
    }
    await windowManager.focus();
  }

  static Future<void> _quitApp() async {
    await _tray.destroy();
    exit(0);
  }

  /// Ẩn window vào tray
  static Future<void> hideToTray() async {
    await windowManager.hide();
    // setSkipTaskbar chỉ hoạt động trên Windows/Linux, macOS không cần
    if (!Platform.isMacOS) {
      await windowManager.setSkipTaskbar(true);
    }
  }

  /// Đọc setting close behavior: 'tray' hoặc 'exit'
  static Future<String> getCloseBehavior() async {
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
