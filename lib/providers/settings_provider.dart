import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/python_info.dart';
import '../screens/home_screen.dart';
import '../services/docker_install_service.dart';
import '../services/postgres_service.dart';
import '../services/python_checker_service.dart';
import '../services/storage_service.dart';

class SettingsState {
  // Python
  final List<PythonInfo>? pythonResults;
  final bool pythonLoading;

  // Docker
  final bool? dockerInstalled;
  final bool? dockerRunning;
  final bool startingDocker;
  final String? dockerVersion;
  final String? dockerComposeVersion;

  // PostgreSQL
  final bool? pgInstalled;
  final String? pgVersion;
  final Map<String, String?>? pgTools;
  final List<PgServerInfo>? pgServers;
  final bool pgActionLoading;

  // Git
  final List<Map<String, dynamic>> gitAccounts;
  final String? defaultGitAccount;
  final bool gitLoaded;

  const SettingsState({
    this.pythonResults,
    this.pythonLoading = false,
    this.dockerInstalled,
    this.dockerRunning,
    this.startingDocker = false,
    this.dockerVersion,
    this.dockerComposeVersion,
    this.pgInstalled,
    this.pgVersion,
    this.pgTools,
    this.pgServers,
    this.pgActionLoading = false,
    this.gitAccounts = const [],
    this.defaultGitAccount,
    this.gitLoaded = false,
  });

  SettingsState copyWith({
    List<PythonInfo>? pythonResults,
    bool? pythonLoading,
    bool? dockerInstalled,
    bool? dockerRunning,
    bool? startingDocker,
    String? dockerVersion,
    String? dockerComposeVersion,
    bool? pgInstalled,
    String? pgVersion,
    Map<String, String?>? pgTools,
    List<PgServerInfo>? Function()? pgServers,
    bool? pgActionLoading,
    List<Map<String, dynamic>>? gitAccounts,
    String? Function()? defaultGitAccount,
    bool? gitLoaded,
  }) {
    return SettingsState(
      pythonResults: pythonResults ?? this.pythonResults,
      pythonLoading: pythonLoading ?? this.pythonLoading,
      dockerInstalled: dockerInstalled ?? this.dockerInstalled,
      dockerRunning: dockerRunning ?? this.dockerRunning,
      startingDocker: startingDocker ?? this.startingDocker,
      dockerVersion: dockerVersion ?? this.dockerVersion,
      dockerComposeVersion: dockerComposeVersion ?? this.dockerComposeVersion,
      pgInstalled: pgInstalled ?? this.pgInstalled,
      pgVersion: pgVersion ?? this.pgVersion,
      pgTools: pgTools ?? this.pgTools,
      pgServers: pgServers != null ? pgServers() : this.pgServers,
      pgActionLoading: pgActionLoading ?? this.pgActionLoading,
      gitAccounts: gitAccounts ?? this.gitAccounts,
      defaultGitAccount: defaultGitAccount != null
          ? defaultGitAccount()
          : this.defaultGitAccount,
      gitLoaded: gitLoaded ?? this.gitLoaded,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  final _pythonChecker = PythonCheckerService();

  @override
  SettingsState build() {
    scanEnvironment();
    return const SettingsState(pythonLoading: true);
  }

  Future<void> scanEnvironment() async {
    state = state.copyWith(pythonLoading: true);
    try {
      final results = await _pythonChecker.detectAll();
      final dInstalled = await DockerInstallService.isInstalled();
      final dRunning =
          dInstalled ? await DockerInstallService.isRunning() : false;
      final dVersion =
          dInstalled ? await DockerInstallService.getVersion() : null;
      final dCompose =
          dInstalled ? await DockerInstallService.getComposeVersion() : null;
      final pgInstalled = await PostgresService.isInstalled();
      final pgVersion =
          pgInstalled ? await PostgresService.getVersion() : null;
      final pgTools = await PostgresService.detectClientTools();

      state = state.copyWith(
        pythonResults: results,
        dockerInstalled: dInstalled,
        dockerRunning: dRunning,
        dockerVersion: dVersion,
        dockerComposeVersion: dCompose,
        pgInstalled: pgInstalled,
        pgVersion: pgVersion,
        pgTools: pgTools,
        pythonLoading: false,
      );
      // Update banner in HomeScreen
      HomeScreen.recheckDocker();
      // Server detection runs separately - don't block main scan
      scanPgServers();
    } catch (_) {
      state = state.copyWith(pythonLoading: false);
    }
  }

  Future<void> scanPgServers() async {
    state = state.copyWith(pgServers: () => null); // show loading
    try {
      final servers = await PostgresService.detectServers();
      state = state.copyWith(pgServers: () => servers);
    } catch (_) {
      state = state.copyWith(pgServers: () => []);
    }
  }

  Future<void> startDocker() async {
    state = state.copyWith(startingDocker: true);
    try {
      await DockerInstallService.startDaemon();
      // Wait for daemon to become ready (retry up to 30s)
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await DockerInstallService.isRunning()) break;
      }
    } catch (_) {}
    state = state.copyWith(startingDocker: false);
    await scanEnvironment();
  }

  void addPythonResult(PythonInfo info) {
    state = state.copyWith(
      pythonResults: [...?state.pythonResults, info],
    );
  }

  PythonCheckerService get pythonChecker => _pythonChecker;

  // ── Git ──

  Future<void> loadGitAccounts() async {
    if (state.gitLoaded) return;
    final settings = await StorageService.loadSettings();
    final accounts = (settings['gitAccounts'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final defaultName = (settings['defaultGitAccount'] ?? '').toString();
    state = state.copyWith(
      gitAccounts: accounts,
      defaultGitAccount: () => defaultName.isEmpty ? null : defaultName,
      gitLoaded: true,
    );
  }

  Future<void> _saveGitAccounts() async {
    final settings = await StorageService.loadSettings();
    settings['gitAccounts'] = state.gitAccounts;
    settings['defaultGitAccount'] = state.defaultGitAccount ?? '';
    // Backward compatibility: save default account token to gitToken
    final def = state.gitAccounts
        .where((a) => a['name'] == state.defaultGitAccount)
        .firstOrNull;
    settings['gitToken'] = def?['token'] ?? '';
    await StorageService.saveSettings(settings);
  }

  void addGitAccount(Map<String, dynamic> account) {
    final accounts = [...state.gitAccounts, account];
    state = state.copyWith(
      gitAccounts: accounts,
      defaultGitAccount: accounts.length == 1
          ? () => account['name'] as String?
          : null,
    );
    _saveGitAccounts();
  }

  void editGitAccount(int index, Map<String, dynamic> account) {
    final oldName = state.gitAccounts[index]['name'];
    final accounts = [...state.gitAccounts];
    accounts[index] = account;
    state = state.copyWith(
      gitAccounts: accounts,
      defaultGitAccount: state.defaultGitAccount == oldName
          ? () => account['name'] as String?
          : null,
    );
    _saveGitAccounts();
  }

  void deleteGitAccount(int index) {
    final name = state.gitAccounts[index]['name'];
    final accounts = [...state.gitAccounts]..removeAt(index);
    state = state.copyWith(
      gitAccounts: accounts,
      defaultGitAccount: state.defaultGitAccount == name
          ? () => accounts.isNotEmpty
              ? accounts.first['name'] as String?
              : null
          : null,
    );
    _saveGitAccounts();
  }

  void setDefaultGitAccount(String name) {
    state = state.copyWith(defaultGitAccount: () => name);
    _saveGitAccounts();
  }

  // ── PostgreSQL actions ──

  Future<void> pgContainerAction(
      String container, Future<bool> Function(String) action) async {
    if (state.pgActionLoading) return;
    state = state.copyWith(pgActionLoading: true);
    await action(container);
    await scanPgServers();
    state = state.copyWith(pgActionLoading: false);
  }

  Future<void> pgLocalStartAction() async {
    if (state.pgActionLoading) return;
    state = state.copyWith(pgActionLoading: true);
    await PostgresService.startLocalService();
    await scanPgServers();
    state = state.copyWith(pgActionLoading: false);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
