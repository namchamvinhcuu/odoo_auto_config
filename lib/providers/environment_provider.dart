import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/models/python_info.dart';
import 'package:odoo_auto_config/services/docker_install_service.dart';
import 'package:odoo_auto_config/services/git_service.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/python_checker_service.dart';
import 'package:odoo_auto_config/services/python_install_service.dart';

class EnvironmentState {
  final bool loading;
  final bool? gitInstalled;
  final String? gitVersion;
  final bool? dockerInstalled;
  final bool? dockerRunning;
  final String? dockerVersion;
  final List<PythonInfo>? pythonResults;
  final bool hasNginxConfig;
  final bool? vscodeInstalled;
  final bool startingDocker;
  final bool autoInstalling;
  final List<String> autoLog;

  const EnvironmentState({
    this.loading = false,
    this.gitInstalled,
    this.gitVersion,
    this.dockerInstalled,
    this.dockerRunning,
    this.dockerVersion,
    this.pythonResults,
    this.hasNginxConfig = false,
    this.vscodeInstalled,
    this.startingDocker = false,
    this.autoInstalling = false,
    this.autoLog = const [],
  });

  EnvironmentState copyWith({
    bool? loading,
    bool? gitInstalled,
    String? gitVersion,
    bool? dockerInstalled,
    bool? dockerRunning,
    String? dockerVersion,
    List<PythonInfo>? pythonResults,
    bool? hasNginxConfig,
    bool? vscodeInstalled,
    bool? startingDocker,
    bool? autoInstalling,
    List<String>? autoLog,
  }) {
    return EnvironmentState(
      loading: loading ?? this.loading,
      gitInstalled: gitInstalled ?? this.gitInstalled,
      gitVersion: gitVersion ?? this.gitVersion,
      dockerInstalled: dockerInstalled ?? this.dockerInstalled,
      dockerRunning: dockerRunning ?? this.dockerRunning,
      dockerVersion: dockerVersion ?? this.dockerVersion,
      pythonResults: pythonResults ?? this.pythonResults,
      hasNginxConfig: hasNginxConfig ?? this.hasNginxConfig,
      vscodeInstalled: vscodeInstalled ?? this.vscodeInstalled,
      startingDocker: startingDocker ?? this.startingDocker,
      autoInstalling: autoInstalling ?? this.autoInstalling,
      autoLog: autoLog ?? this.autoLog,
    );
  }
}

/// Return value from autoSetup when Windows needs restart for WSL
enum AutoSetupResult { done, needsRestart }

class EnvironmentNotifier extends Notifier<EnvironmentState> {
  final _pythonChecker = PythonCheckerService();

  @override
  EnvironmentState build() {
    checkAll();
    return const EnvironmentState(loading: true);
  }

  Future<void> checkAll() async {
    state = state.copyWith(loading: true);
    try {
      final results = await Future.wait([
        GitService.isInstalled(),
        GitService.getVersion(),
        DockerInstallService.isInstalled(),
        _pythonChecker.detectAll(),
        PlatformService.isVscodeInstalled(),
        NginxService.loadSettings(),
      ]);

      final gitOk = results[0] as bool;
      final gitVer = results[1] as String?;
      final dockerOk = results[2] as bool;
      final pyResults = results[3] as List<PythonInfo>;
      final vsOk = results[4] as bool;
      final nginx = results[5] as Map<String, dynamic>;

      final dockerRunning =
          dockerOk ? await DockerInstallService.isRunning() : false;
      final dockerVer =
          dockerOk ? await DockerInstallService.getVersion() : null;

      state = state.copyWith(
        loading: false,
        gitInstalled: gitOk,
        gitVersion: gitVer,
        dockerInstalled: dockerOk,
        dockerRunning: dockerRunning,
        dockerVersion: dockerVer,
        pythonResults: pyResults,
        vscodeInstalled: vsOk,
        hasNginxConfig: (nginx['confDir'] ?? '').toString().isNotEmpty,
      );
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> startDocker() async {
    state = state.copyWith(startingDocker: true);
    try {
      await DockerInstallService.startDaemon();
      for (var i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await DockerInstallService.isRunning()) break;
      }
    } catch (_) {}
    await checkAll();
    state = state.copyWith(startingDocker: false);
  }

  /// Returns [AutoSetupResult.needsRestart] if Windows needs restart for WSL.
  Future<AutoSetupResult> autoSetup() async {
    state = state.copyWith(autoInstalling: true, autoLog: []);

    void log(String line) {
      state = state.copyWith(autoLog: [...state.autoLog, line]);
    }

    // 1. Git
    await checkAll();
    if (state.gitInstalled != true) {
      log('');
      log('━━━ Git ━━━');
      await GitService.install(log);
      await checkAll();
    }

    // 2. Python
    if (state.pythonResults == null || state.pythonResults!.isEmpty) {
      log('');
      log('━━━ Python ━━━');
      await PythonInstallService.install('3.11', log);
      await checkAll();
    }

    // 3. VSCode
    if (state.vscodeInstalled != true) {
      log('');
      log('━━━ VSCode ━━━');
      final cmd = PlatformService.vscodeInstallCommand();
      log('[+] Running: ${cmd.description}');
      try {
        final result = await Process.run(
          cmd.executable,
          cmd.args,
          runInShell: true,
        );
        if (result.exitCode == 0) {
          log('[+] VSCode installed successfully!');
        } else {
          log('[ERROR] VSCode installation failed');
        }
      } catch (e) {
        log('[ERROR] $e');
      }
      await checkAll();
    }

    // 4. Docker
    if (state.dockerInstalled != true) {
      log('');
      log('━━━ Docker ━━━');
      if (PlatformService.isWindows) {
        final wslOk = await DockerInstallService.isWslInstalled();
        if (!wslOk) {
          log('[+] WSL not found. Installing WSL...');
          await DockerInstallService.install(log);
          state = state.copyWith(autoInstalling: false);
          return AutoSetupResult.needsRestart;
        }
      }
      await DockerInstallService.install(log);
      await checkAll();
    }

    log('');
    log('[+] Auto setup complete!');
    state = state.copyWith(autoInstalling: false);
    return AutoSetupResult.done;
  }
}

final environmentProvider =
    NotifierProvider<EnvironmentNotifier, EnvironmentState>(
        EnvironmentNotifier.new);
