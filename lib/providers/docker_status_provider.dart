import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/docker_install_service.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';

class DockerStatus {
  final bool? installed;
  final bool? running;
  final bool dismissed;

  const DockerStatus({this.installed, this.running, this.dismissed = false});

  bool get showBanner =>
      !dismissed &&
      (installed == false || (installed == true && running != true));
}

class DockerStatusNotifier extends Notifier<DockerStatus> {
  Timer? _pollTimer;

  @override
  DockerStatus build() {
    ref.onDispose(() => _pollTimer?.cancel());
    Future.microtask(() => check());
    return const DockerStatus();
  }

  Future<void> check() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final installed = await DockerInstallService.isInstalled();
      final running = installed ? await DockerInstallService.isRunning() : false;

      state = DockerStatus(installed: installed, running: running);

      if (!installed || running) break;
      if (attempt < 2) {
        await Future.delayed(const Duration(seconds: 5));
      }
    }

    if (state.installed == true && state.running == true) {
      _pollTimer?.cancel();
      await _autoStartNginx();
    } else if (state.showBanner) {
      // Docker installed but not running → poll every 10s until it starts
      _startPolling();
    }
  }

  /// Periodically recheck Docker status until it's running.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final installed = await DockerInstallService.isInstalled();
      final running = installed ? await DockerInstallService.isRunning() : false;
      state = DockerStatus(installed: installed, running: running);
      if (running) {
        _pollTimer?.cancel();
        _pollTimer = null;
        await _autoStartNginx();
      }
    });
  }

  /// Dismiss the banner and stop polling.
  void dismiss() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state = DockerStatus(
      installed: state.installed,
      running: state.running,
      dismissed: true,
    );
  }

  Future<void> _autoStartNginx() async {
    final nginx = await NginxService.loadSettings();
    final container = (nginx['containerName'] ?? '').toString();
    if (container.isEmpty) return;

    final running = await NginxService.isDockerContainerRunning(container);
    if (running) return;

    try {
      final docker = await PlatformService.dockerPath;
      await Process.run(docker, ['start', container], runInShell: true);
    } catch (_) {}
  }
}

final dockerStatusProvider =
    NotifierProvider<DockerStatusNotifier, DockerStatus>(
        DockerStatusNotifier.new);
