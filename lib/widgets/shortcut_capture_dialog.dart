import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/shortcut_service.dart';

/// Modal dialog that captures a single shortcut combination.
///
/// Returns the captured [ShortcutSpec] via Navigator.pop, or null on cancel.
/// Open with [AppDialog.show] so it is draggable and non-dismissible by
/// clicking outside.
class ShortcutCaptureDialog extends StatefulWidget {
  final String actionLabel;
  final ShortcutSpec? initial;

  const ShortcutCaptureDialog({
    super.key,
    required this.actionLabel,
    this.initial,
  });

  @override
  State<ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<ShortcutCaptureDialog> {
  ShortcutSpec? _captured;

  @override
  void initState() {
    super.initState();
    _captured = widget.initial;
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    super.dispose();
  }

  static bool _isModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.alt;
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // Let ESC propagate so AppDialog's CallbackShortcuts can close the dialog.
    if (event.logicalKey == LogicalKeyboardKey.escape) return false;

    // Ignore modifier-only presses; wait for a trigger key. Still consume them
    // so they don't bubble into other handlers while the dialog is open.
    if (_isModifier(event.logicalKey)) return true;

    final kb = HardwareKeyboard.instance;
    setState(() {
      _captured = ShortcutSpec(
        ctrl: kb.isControlPressed,
        meta: kb.isMetaPressed,
        shift: kb.isShiftPressed,
        alt: kb.isAltPressed,
        triggerKeyId: event.logicalKey.keyId,
      );
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captured = _captured;
    final isValid = captured != null && captured.hasAnyModifier;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(context.l10n.shortcutsCaptureTitle)),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.shortcutsCaptureFor(widget.actionLabel),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xxl,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.mediumBorderRadius,
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              child: Center(
                child: captured == null
                    ? Text(
                        context.l10n.shortcutsCaptureHint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        captured.format(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            if (captured != null && !captured.hasAnyModifier) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.warning_amber,
                      color: Colors.orange, size: AppIconSize.md),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      context.l10n.shortcutsInvalidHint,
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: AppFontSize.sm,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: isValid
              ? () => Navigator.pop<ShortcutSpec>(context, captured)
              : null,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
