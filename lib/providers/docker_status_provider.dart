import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/docker_install_service.dart';
import 'package:odoo_auto_config/services/nginx_service.dart';
import 'package:odoo_auto_config/services/platform_service.dart';

class DockerStatus {
  final bool? installed;
  final bool? running;

  const DockerStatus({this.installed, this.running});

  bool get showBanner => installed == false || (installed == true && running != true);
}

class DockerStatusNotifier extends Notifier<DockerStatus> {
  @override
  DockerStatus build() {
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
      await _autoStartNginx();
    }
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
