import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/models/venv_info.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'package:odoo_auto_config/services/venv_service.dart';

class VenvState {
  final List<VenvInfo> registeredVenvs;
  final bool loading;

  const VenvState({
    this.registeredVenvs = const [],
    this.loading = false,
  });

  VenvState copyWith({
    List<VenvInfo>? registeredVenvs,
    bool? loading,
  }) {
    return VenvState(
      registeredVenvs: registeredVenvs ?? this.registeredVenvs,
      loading: loading ?? this.loading,
    );
  }
}

class VenvNotifier extends AsyncNotifier<VenvState> {
  final _venvService = VenvService();

  @override
  Future<VenvState> build() async {
    final venvs = await _loadVenvs();
    return VenvState(registeredVenvs: venvs);
  }

  Future<List<VenvInfo>> _loadVenvs() async {
    final saved = await StorageService.loadRegisteredVenvs();
    final List<VenvInfo> venvs = [];
    for (final json in saved) {
      final info = VenvInfo.fromJson(json);
      final inspected = await _venvService.inspectVenv(info.path);
      if (inspected != null) {
        venvs.add(VenvInfo(
          path: inspected.path,
          pythonVersion: inspected.pythonVersion,
          pipVersion: inspected.pipVersion,
          isValid: inspected.isValid,
          label: info.label,
        ));
      } else {
        venvs.add(VenvInfo(
          path: info.path,
          pythonVersion: info.pythonVersion,
          pipVersion: info.pipVersion,
          isValid: false,
          label: info.label,
        ));
      }
    }
    return venvs;
  }

  Future<void> reload() async {
    final venvs = await _loadVenvs();
    state = AsyncData(VenvState(registeredVenvs: venvs));
  }

  Future<void> register(VenvInfo venv) async {
    await StorageService.addRegisteredVenv(venv.toJson());
    await reload();
  }

  Future<void> remove(String path) async {
    await StorageService.removeRegisteredVenv(path);
    await reload();
  }

  Future<void> updateVenv(VenvInfo venv) async {
    await StorageService.addRegisteredVenv(venv.toJson());
    await reload();
  }
}

final venvProvider =
    AsyncNotifierProvider<VenvNotifier, VenvState>(VenvNotifier.new);
