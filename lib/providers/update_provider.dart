import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/update_service.dart';

class UpdateState {
  final UpdateInfo? info;
  final bool updating;

  const UpdateState({this.info, this.updating = false});

  bool get hasUpdate => info != null && info!.hasUpdate;
}

class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() {
    checkForUpdate();
    return const UpdateState();
  }

  Future<void> checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (info != null && info.hasUpdate) {
      state = UpdateState(info: info);
    }
  }

  /// Returns true if install succeeded (app will relaunch), false on failure.
  Future<bool> performUpdate() async {
    final info = state.info;
    if (info == null || info.downloadUrl == null || info.assetName == null) {
      return false;
    }
    state = UpdateState(info: info, updating: true);

    final path = await UpdateService.download(info.downloadUrl!, info.assetName!);
    if (path == null) {
      state = UpdateState(info: info, updating: false);
      return false;
    }

    final installed = await UpdateService.install(path);
    if (!installed) {
      try { File(path).deleteSync(); } catch (_) {}
      state = UpdateState(info: info, updating: false);
      return false;
    }
    return true;
  }

  void dismiss() {
    state = const UpdateState();
  }
}

final updateProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);
