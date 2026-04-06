import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/models/profile.dart';
import 'package:odoo_auto_config/models/venv_info.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

class ProfileState {
  final List<Profile> profiles;
  final List<VenvInfo> venvs;

  const ProfileState({
    this.profiles = const [],
    this.venvs = const [],
  });
}

class ProfileNotifier extends AsyncNotifier<ProfileState> {
  @override
  Future<ProfileState> build() => _load();

  Future<ProfileState> _load() async {
    final profilesJson = await StorageService.loadProfiles();
    final venvsJson = await StorageService.loadRegisteredVenvs();
    return ProfileState(
      profiles: profilesJson.map((j) => Profile.fromJson(j)).toList(),
      venvs: venvsJson.map((j) => VenvInfo.fromJson(j)).toList(),
    );
  }

  Future<void> addOrUpdate(Profile profile) async {
    await StorageService.addOrUpdateProfile(profile.toJson());
    state = AsyncData(await _load());
  }

  Future<void> remove(String id) async {
    await StorageService.removeProfile(id);
    state = AsyncData(await _load());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, ProfileState>(ProfileNotifier.new);
