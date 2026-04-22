import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/shortcut_provider.dart';
import 'package:odoo_auto_config/services/shortcut_service.dart';
import 'package:odoo_auto_config/widgets/shortcut_capture_dialog.dart';

class ShortcutsTab extends ConsumerWidget {
  const ShortcutsTab({super.key});

  String _actionLabel(BuildContext context, String actionId) {
    switch (actionId) {
      case ShortcutActions.newWindow:
        return context.l10n.newWindow;
      default:
        return ShortcutService.defaultActionLabel(actionId);
    }
  }

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    String actionId,
    ShortcutSpec? current,
  ) async {
    final label = _actionLabel(context, actionId);
    final notifier = ref.read(shortcutProvider.notifier);
    notifier.setCapturing(true);
    try {
      final result = await AppDialog.show<ShortcutSpec>(
        context: context,
        builder: (_) => ShortcutCaptureDialog(
          actionLabel: label,
          initial: current,
        ),
      );
      if (result != null) {
        await notifier.setShortcut(actionId, result);
      }
    } finally {
      notifier.setCapturing(false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shortcutProvider);
    final notifier = ref.read(shortcutProvider.notifier);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.shortcutsTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => notifier.resetAll(),
                icon: const Icon(Icons.restore, size: AppIconSize.md),
                label: Text(context.l10n.shortcutsResetAll),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.shortcutsSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final actionId in ShortcutActions.all)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ShortcutRow(
                label: _actionLabel(context, actionId),
                spec: state.shortcuts[actionId],
                onChange: () => _change(
                  context,
                  ref,
                  actionId,
                  state.shortcuts[actionId],
                ),
                onReset: () => notifier.resetShortcut(actionId),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String label;
  final ShortcutSpec? spec;
  final VoidCallback onChange;
  final VoidCallback onReset;

  const _ShortcutRow({
    required this.label,
    required this.spec,
    required this.onChange,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.mediumBorderRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppRadius.smallBorderRadius,
            ),
            child: Text(
              spec?.format() ?? '—',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: onChange,
            icon: const Icon(Icons.edit, size: AppIconSize.md),
            tooltip: context.l10n.shortcutsChange,
          ),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.restore, size: AppIconSize.md),
            tooltip: context.l10n.shortcutsReset,
          ),
        ],
      ),
    );
  }
}
