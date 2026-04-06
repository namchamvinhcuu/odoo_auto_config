import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/settings_provider.dart';
import 'git_account_dialog.dart';

class GitTab extends ConsumerWidget {
  const GitTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    // Trigger lazy load
    notifier.loadGitAccounts();

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.gitSettingsTitle,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(context.l10n.gitSettingsDescription,
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: AppFontSize.md)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _addGitAccount(context, notifier),
                icon: const Icon(Icons.add),
                label: const Text('Add Account'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (s.gitAccounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  'No Git accounts configured',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ...List.generate(s.gitAccounts.length, (i) {
              final account = s.gitAccounts[i];
              final name = account['name'] ?? '';
              final username = account['username'] ?? '';
              final email = account['email'] ?? '';
              final isDefault = s.defaultGitAccount == name;
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                color: isDefault
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3)
                    : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isDefault
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      if (isDefault) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const Chip(
                          label: Text('Default'),
                          labelStyle: TextStyle(fontSize: AppFontSize.sm),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '$username • $email',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.sm,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isDefault)
                        IconButton(
                          onPressed: () =>
                              notifier.setDefaultGitAccount(name),
                          icon: const Icon(Icons.star_border),
                          tooltip: 'Set as default',
                        ),
                      IconButton(
                        onPressed: () =>
                            _editGitAccount(context, notifier, i, account),
                        icon: const Icon(Icons.edit),
                        tooltip: context.l10n.edit,
                      ),
                      IconButton(
                        onPressed: () => notifier.deleteGitAccount(i),
                        icon: const Icon(Icons.delete),
                        color: Colors.red,
                        tooltip: context.l10n.removeFromList,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _addGitAccount(BuildContext context, SettingsNotifier notifier) {
    AppDialog.show(
      context: context,
      builder: (ctx) => GitAccountDialog(),
    ).then((result) {
      if (result == null) return;
      notifier.addGitAccount(result as Map<String, dynamic>);
    });
  }

  void _editGitAccount(BuildContext context, SettingsNotifier notifier,
      int index, Map<String, dynamic> existing) {
    AppDialog.show(
      context: context,
      builder: (ctx) => GitAccountDialog(existing: existing),
    ).then((result) {
      if (result == null) return;
      notifier.editGitAccount(index, result as Map<String, dynamic>);
    });
  }
}
