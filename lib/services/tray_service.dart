import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:odoo_auto_config/services/instance_service.dart';

class TrayService {
  static final SystemTray _tray = SystemTray();
  static bool _initialized = false;

  /// System tray supported on macOS, Windows, Linux
  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Initialize system tray (only called by tray owner instance).
  static Future<void> init() async {
    if (_initialized || !supported) return;

    final iconPath =
        Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';

    await _tray.initSystemTray(
      title: '',
      iconPath: iconPath,
      toolTip: 'Workspace Configuration',
    );

    await rebuildMenu();

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

  /// Rebuild the tray context menu with current instance list.
  static Future<void> rebuildMenu() async {
    final instances = await InstanceService.listInstances();
    final myPid = pid;

    final showChildren = instances.map((inst) {
      final instPid = inst['pid'] as int;
      final label = (inst['displayLabel'] ?? inst['label']) as String;
      return MenuItemLabel(
        label: label,
        onClicked: (_) {
          if (instPid == myPid) {
            _showWindow();
          } else {
            InstanceService.signalShow(instPid);
          }
        },
      );
    }).toList();

    final menu = Menu();
    await menu.buildFrom([
      SubMenu(label: 'Show', children: showChildren),
      MenuSeparator(),
      MenuItemLabel(
        label: 'New Window',
        onClicked: (_) => InstanceService.launchNewInstance(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit All',
        onClicked: (_) => _quitAll(),
      ),
    ]);
    await _tray.setContextMenu(menu);
  }

  static Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> _quitAll() async {
    await InstanceService.signalQuitAll();
    // Give other instances time to receive the signal, then exit self
    await Future.delayed(const Duration(milliseconds: 500));
    await cleanup();
    exit(0);
  }

  /// Hide window to tray (minimize to system tray).
  static Future<void> hideToTray() async {
    await windowManager.hide();
  }

  /// Cleanup: destroy tray icon and instance registry.
  static Future<void> cleanup() async {
    if (_initialized) {
      await _tray.destroy();
      _initialized = false;
    }
    await InstanceService.cleanup();
  }
}
