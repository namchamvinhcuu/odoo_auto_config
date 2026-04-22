import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/git_discard_service.dart';

/// Confirm-only dialog. Lists the files that will be discarded and warns the
/// user that the action is not recoverable. Returns `true` via Navigator.pop
/// when the user clicks Discard, `null`/`false` otherwise.
///
/// Open with [AppDialog.show] so it is draggable and non-dismissible on
/// barrier tap.
class DiscardConfirmDialog extends StatelessWidget {
  final List<DiscardItem> items;

  const DiscardConfirmDialog({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final untrackedCount = items.where((i) => i.isUntracked).length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber,
              color: Colors.orange, size: AppIconSize.lg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(context.l10n.discardTitle)),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.discardConfirmMessage(items.length),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.discardWarning,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (untrackedCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                context.l10n.discardUntrackedWarning(untrackedCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade700,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Container(
              constraints: const BoxConstraints(
                maxHeight: AppDialog.listHeight,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade600),
                borderRadius: AppRadius.mediumBorderRadius,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${item.status.padRight(2)}  ',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: item.isUntracked
                                  ? Colors.orange
                                  : theme.colorScheme.primary,
                              fontSize: AppFontSize.md,
                            ),
                          ),
                          TextSpan(
                            text: item.file,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: AppFontSize.md,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.delete_forever, size: AppIconSize.md),
          label: Text(context.l10n.discardAction),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
        ),
      ],
    );
  }
}
