import 'dart:io';
import 'package:flutter/services.dart';

/// Action identifiers. Add new actions here when making more shortcuts customizable.
class ShortcutActions {
  static const String newWindow = 'newWindow';

  static const List<String> all = [newWindow];
}

/// A keyboard shortcut combination: modifier flags + one trigger key.
///
/// Serialized as `{ctrl, meta, shift, alt, key}` where `key` is the
/// LogicalKeyboardKey.keyId of the non-modifier trigger.
class ShortcutSpec {
  final bool ctrl;
  final bool meta;
  final bool shift;
  final bool alt;
  final int triggerKeyId;

  const ShortcutSpec({
    this.ctrl = false,
    this.meta = false,
    this.shift = false,
    this.alt = false,
    required this.triggerKeyId,
  });

  bool get hasAnyModifier => ctrl || meta || shift || alt;

  Map<String, dynamic> toJson() => {
        'ctrl': ctrl,
        'meta': meta,
        'shift': shift,
        'alt': alt,
        'key': triggerKeyId,
      };

  factory ShortcutSpec.fromJson(Map<String, dynamic> json) => ShortcutSpec(
        ctrl: json['ctrl'] as bool? ?? false,
        meta: json['meta'] as bool? ?? false,
        shift: json['shift'] as bool? ?? false,
        alt: json['alt'] as bool? ?? false,
        triggerKeyId: json['key'] as int,
      );

  /// Match against a key event. Requires exact modifier state (extra modifiers
  /// held → no match) so Cmd+N does not fire when Cmd+Shift+N is pressed.
  bool matches(KeyDownEvent event) {
    if (event.logicalKey.keyId != triggerKeyId) return false;
    final kb = HardwareKeyboard.instance;
    return kb.isControlPressed == ctrl &&
        kb.isMetaPressed == meta &&
        kb.isShiftPressed == shift &&
        kb.isAltPressed == alt;
  }

  /// Format for display. macOS uses symbol glyphs (⌘⌥⇧⌃), others use text+`+`.
  String format() {
    final parts = <String>[];
    if (Platform.isMacOS) {
      if (ctrl) parts.add('⌃');
      if (alt) parts.add('⌥');
      if (shift) parts.add('⇧');
      if (meta) parts.add('⌘');
      parts.add(_keyLabel(triggerKeyId));
      return parts.join();
    }
    if (ctrl) parts.add('Ctrl');
    if (alt) parts.add('Alt');
    if (shift) parts.add('Shift');
    if (meta) parts.add('Meta');
    parts.add(_keyLabel(triggerKeyId));
    return parts.join('+');
  }

  static String _keyLabel(int keyId) {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) return '?';
    final label = key.keyLabel;
    if (label.isEmpty) return key.debugName ?? '?';
    return label.length == 1 ? label.toUpperCase() : label;
  }

  @override
  bool operator ==(Object other) =>
      other is ShortcutSpec &&
      other.ctrl == ctrl &&
      other.meta == meta &&
      other.shift == shift &&
      other.alt == alt &&
      other.triggerKeyId == triggerKeyId;

  @override
  int get hashCode => Object.hash(ctrl, meta, shift, alt, triggerKeyId);
}

/// Platform-aware default shortcut bindings.
class ShortcutService {
  static Map<String, ShortcutSpec> defaults() {
    if (Platform.isMacOS) {
      return {
        ShortcutActions.newWindow: ShortcutSpec(
          meta: true,
          triggerKeyId: LogicalKeyboardKey.keyN.keyId,
        ),
      };
    }
    return {
      ShortcutActions.newWindow: ShortcutSpec(
        ctrl: true,
        triggerKeyId: LogicalKeyboardKey.keyN.keyId,
      ),
    };
  }

  /// Label shown next to each configurable action. Wired through l10n in UI;
  /// falls back to English here so this file stays pure.
  static String defaultActionLabel(String actionId) {
    switch (actionId) {
      case ShortcutActions.newWindow:
        return 'New Window';
      default:
        return actionId;
    }
  }
}
