import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import '../../models/profile.dart';
import '../../models/venv_info.dart';
import '../../services/storage_service.dart';
import 'profile_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Profile> _profiles = [];
  List<VenvInfo> _venvs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profilesJson = await StorageService.loadProfiles();
    final venvsJson = await StorageService.loadRegisteredVenvs();
    setState(() {
      _profiles = profilesJson.map((j) => Profile.fromJson(j)).toList();
      _venvs = venvsJson.map((j) => VenvInfo.fromJson(j)).toList();
      _loading = false;
    });
  }

  Future<void> _createOrEdit([Profile? existing]) async {
    final result = await AppDialog.show<Profile>(
      context: context,
      builder: (ctx) => ProfileDialog(
        profile: existing,
        venvs: _venvs,
      ),
    );
    if (result != null) {
      await StorageService.addOrUpdateProfile(result.toJson());
      await _load();
    }
  }

  Future<void> _delete(Profile profile) async {
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
      await StorageService.removeProfile(profile.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: () => _createOrEdit(),
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
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (_profiles.isEmpty)
            Expanded(
              child: Center(
                child: Text(context.l10n.profilesEmpty),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _profiles.length,
                itemBuilder: (context, index) {
                  final p = _profiles[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text('${p.odooVersion}'),
                      ),
                      title: Text(p.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.venvLabel(p.venvPath),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.xl)),
                          Text(context.l10n.odooBinLabel(p.odooBinPath),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.xl)),
                          Text(context.l10n.odooSrcLabel(p.odooSourcePath),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.xl)),
                          Text(
                              context.l10n.dbLabel(p.dbUser, p.dbHost,
                                  p.dbPort.toString()),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.xl)),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _createOrEdit(p),
                            icon: const Icon(Icons.edit),
                            tooltip: context.l10n.edit,
                          ),
                          IconButton(
                            onPressed: () => _delete(p),
                            icon: const Icon(Icons.delete),
                            color: Colors.red,
                            tooltip: context.l10n.delete,
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
    );
  }
}
