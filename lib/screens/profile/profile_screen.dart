import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/models/profile.dart';
import 'package:odoo_auto_config/providers/profile_provider.dart';
import 'profile_dialog.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(profileProvider);

    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(context.l10n.profilesTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _createOrEdit(context, ref),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.newProfile),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.profilesSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Expanded(
            child: asyncState.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (state) {
                if (state.profiles.isEmpty) {
                  return Center(
                    child: Text(context.l10n.profilesEmpty),
                  );
                }
                return ListView.builder(
                  itemCount: state.profiles.length,
                  itemBuilder: (context, index) {
                    final p = state.profiles[index];
                    return _buildProfileCard(context, ref, p);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(
      BuildContext context, WidgetRef ref, Profile p) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          child: Text('${p.odooVersion}'),
        ),
        title:
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.venvLabel(p.venvPath),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: AppFontSize.xl)),
            Text(context.l10n.odooBinLabel(p.odooBinPath),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: AppFontSize.xl)),
            Text(context.l10n.odooSrcLabel(p.odooSourcePath),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: AppFontSize.xl)),
            Text(context.l10n.dbLabel(p.dbUser, p.dbHost, p.dbPort.toString()),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: AppFontSize.xl)),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _createOrEdit(context, ref, existing: p),
              icon: const Icon(Icons.edit),
              tooltip: context.l10n.edit,
            ),
            IconButton(
              onPressed: () => _delete(context, ref, p),
              icon: const Icon(Icons.delete),
              color: Colors.red,
              tooltip: context.l10n.delete,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createOrEdit(BuildContext context, WidgetRef ref,
      {Profile? existing}) async {
    final venvs = ref.read(profileProvider).valueOrNull?.venvs ?? [];
    final result = await AppDialog.show<Profile>(
      context: context,
      builder: (ctx) => ProfileDialog(
        profile: existing,
        venvs: venvs,
      ),
    );
    if (result != null) {
      await ref.read(profileProvider.notifier).addOrUpdate(result);
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Profile profile) async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(context.l10n.deleteProfileTitle),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
        content: Text(context.l10n.deleteProfileConfirm(profile.name)),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.delete)),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(profileProvider.notifier).remove(profile.id);
    }
  }
}
