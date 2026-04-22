import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/shortcut_service.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

class ShortcutState {
  final Map<String, ShortcutSpec> shortcuts;

  /// True while the capture dialog is open. Global key dispatcher skips
  /// dispatching registered shortcuts during capture so the user can press
  /// their new combination without triggering its old action.
  final bool capturing;

  const ShortcutState({this.shortcuts = const {}, this.capturing = false});

  ShortcutState copyWith({
    Map<String, ShortcutSpec>? shortcuts,
    bool? capturing,
  }) =>
      ShortcutState(
        shortcuts: shortcuts ?? this.shortcuts,
        capturing: capturing ?? this.capturing,
      );
}

class ShortcutNotifier extends Notifier<ShortcutState> {
  @override
  ShortcutState build() => ShortcutState(shortcuts: ShortcutService.defaults());

  Future<void> load() async {
    final settings = await StorageService.loadSettings();
    final raw = settings['shortcuts'] as Map<String, dynamic>?;
    final defaults = ShortcutService.defaults();
    final merged = <String, ShortcutSpec>{...defaults};
    if (raw != null) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          try {
            merged[entry.key] = ShortcutSpec.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          } catch (_) {
            // Ignore malformed entries; fall back to default.
          }
        }
      }
    }
    state = state.copyWith(shortcuts: merged);
  }

  Future<void> setShortcut(String actionId, ShortcutSpec spec) async {
    final next = Map<String, ShortcutSpec>.from(state.shortcuts);
    next[actionId] = spec;
    state = state.copyWith(shortcuts: next);
    await _persist();
  }

  Future<void> resetShortcut(String actionId) async {
    final defaults = ShortcutService.defaults();
    final next = Map<String, ShortcutSpec>.from(state.shortcuts);
    if (defaults.containsKey(actionId)) {
      next[actionId] = defaults[actionId]!;
    } else {
      next.remove(actionId);
    }
    state = state.copyWith(shortcuts: next);
    await _persist();
  }

  Future<void> resetAll() async {
    state = state.copyWith(shortcuts: ShortcutService.defaults());
    await _persist();
  }

  void setCapturing(bool value) {
    if (state.capturing == value) return;
    state = state.copyWith(capturing: value);
  }

  /// Find the first action whose shortcut matches the given event.
  /// Returns null when no shortcut matches or when capture is active.
  String? findAction(KeyDownEvent event) {
    if (state.capturing) return null;
    for (final entry in state.shortcuts.entries) {
      if (entry.value.matches(event)) return entry.key;
    }
    return null;
  }

  Future<void> _persist() async {
    await StorageService.updateSettings((settings) {
      settings['shortcuts'] = {
        for (final e in state.shortcuts.entries) e.key: e.value.toJson(),
      };
    });
  }
}

final shortcutProvider =
    NotifierProvider<ShortcutNotifier, ShortcutState>(ShortcutNotifier.new);
