import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/services/command_runner.dart';
import 'package:odoo_auto_config/services/odoo_launch_config_service.dart';
import 'package:odoo_auto_config/services/odoo_server_service.dart';

/// Lifecycle status of a managed Odoo server process.
enum OdooServerStatus {
  /// Never started (or fully stopped and cleared).
  idle,

  /// Process is being spawned / booting, HTTP not up yet.
  starting,

  /// Process spawned and running; HTTP service confirmed up.
  ready,

  /// Process exited or was stopped by the user.
  stopped,

  /// Failed to start (e.g. interpreter not found) or crashed on boot.
  error,
}

/// Immutable snapshot of one project's Odoo server.
class OdooServerState {
  final OdooServerStatus status;
  final List<String> logs;
  final int? pid;

  const OdooServerState({
    this.status = OdooServerStatus.idle,
    this.logs = const [],
    this.pid,
  });

  /// Server process is alive (booting or ready).
  bool get isActive =>
      status == OdooServerStatus.starting || status == OdooServerStatus.ready;

  OdooServerState copyWith({
    OdooServerStatus? status,
    List<String>? logs,
    int? Function()? pid,
  }) =>
      OdooServerState(
        status: status ?? this.status,
        logs: logs ?? this.logs,
        pid: pid != null ? pid() : this.pid,
      );
}

/// Max log lines kept per server (bounds memory for long-running servers).
const int _kMaxLogLines = 5000;

/// Lenient UTF-8 decoder — a malformed byte in the process output must never
/// throw and silently kill the log subscription (odoo boots for minutes).
const _kDecoder = Utf8Decoder(allowMalformed: true);

/// Manages running Odoo server processes keyed by project path.
///
/// Owns the [Process] handles + stdout/stderr subscriptions (kept off the
/// immutable state). State survives dialogs opening/closing; [ref.onDispose]
/// kills everything when the app shuts down so no orphan Odoo processes leak.
class RunningServersNotifier extends Notifier<Map<String, OdooServerState>> {
  final Map<String, Process> _processes = {};
  final Map<String, List<StreamSubscription<String>>> _subs = {};

  @override
  Map<String, OdooServerState> build() {
    ref.onDispose(() {
      for (final path in _processes.keys.toList()) {
        _teardown(path);
      }
    });
    return const {};
  }

  OdooServerState _stateFor(String path) =>
      state[path] ?? const OdooServerState();

  void _setState(String path, OdooServerState next) {
    state = {...state, path: next};
  }

  void _appendLog(String path, String line) {
    final cur = _stateFor(path);
    final logs = List<String>.from(cur.logs)..add(line);
    if (logs.length > _kMaxLogLines) {
      logs.removeRange(0, logs.length - _kMaxLogLines);
    }
    _setState(path, cur.copyWith(logs: logs));
  }

  /// Start (or restart, if already running) the Odoo server for [path].
  ///
  /// Fire-and-forget: status flows starting → ready (on the HTTP log line) →
  /// stopped/error (on exit). Listeners (the log dialog) watch [state] to react
  /// — the browser is opened when the status transitions to [OdooServerStatus.ready],
  /// with no time limit, so a slow first boot (module loading) still opens it.
  Future<void> launch(String path, OdooLaunchConfig config) async {
    // Restart semantics: stop any existing process first.
    await _teardown(path);

    if (!config.isRunnable) {
      _setState(
        path,
        OdooServerState(
          status: OdooServerStatus.error,
          logs: const ['[ERROR] Missing Python interpreter or odoo-bin path.'],
        ),
      );
      return;
    }

    _setState(
      path,
      OdooServerState(
        status: OdooServerStatus.starting,
        logs: [
          '[+] Starting Odoo: ${config.python} ${config.odooBin} '
              '${config.args.join(' ')}',
          '',
        ],
      ),
    );

    try {
      final process = await OdooServerService.start(
        python: config.python!,
        odooBin: config.odooBin!,
        args: config.args,
        workingDirectory: config.workingDirectory,
      );
      _processes[path] = process;
      _setState(path, _stateFor(path).copyWith(pid: () => process.pid));

      void handle(String data) {
        for (final raw in data.split('\n')) {
          final line = CommandRunner.cleanLine(raw);
          if (line == null) continue;
          _appendLog(path, line);
          // Flip to ready on the HTTP line; only from `starting` so a later
          // "longpolling running on" line can't demote a stopped/error server.
          if (isOdooHttpReadyLine(line) &&
              _stateFor(path).status == OdooServerStatus.starting) {
            _setState(
                path, _stateFor(path).copyWith(status: OdooServerStatus.ready));
          }
        }
      }

      void onErr(Object e, StackTrace _) => _appendLog(path, '[WARN] $e');

      // Odoo logging (INFO/WARNING/…) goes to stderr by default — scan both.
      // cancelOnError:false so a transient stream error never stops the log.
      _subs[path] = [
        process.stdout
            .transform(_kDecoder)
            .listen(handle, onError: onErr, cancelOnError: false),
        process.stderr
            .transform(_kDecoder)
            .listen(handle, onError: onErr, cancelOnError: false),
      ];

      unawaited(process.exitCode.then((code) => _onExit(path, code)));

      // Robust readiness: poll the HTTP port until it accepts connections.
      // Independent of log verbosity — a high `log_level` (e.g. error) hides
      // the INFO "HTTP service running" line, so the log-scan alone can miss it.
      if (config.httpPort != null) {
        unawaited(_pollReady(path, config.httpPort!));
      }
    } catch (e) {
      _appendLog(path, '[ERROR] $e');
      _setState(path, _stateFor(path).copyWith(status: OdooServerStatus.error));
    }
  }

  /// Poll [port] until it accepts a TCP connection, then mark the server ready.
  /// Stops as soon as the server leaves the `starting` state (log-scan won the
  /// race, or it stopped/errored/exited).
  Future<void> _pollReady(String path, int port) async {
    while (_processes.containsKey(path) &&
        _stateFor(path).status == OdooServerStatus.starting) {
      await Future.delayed(const Duration(seconds: 1));
      if (_stateFor(path).status != OdooServerStatus.starting) return;
      if (await _isPortListening(port)) {
        if (_stateFor(path).status == OdooServerStatus.starting) {
          _appendLog(path, '[+] Server is up on port $port.');
          _setState(
              path, _stateFor(path).copyWith(status: OdooServerStatus.ready));
        }
        return;
      }
    }
  }

  static Future<bool> _isPortListening(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stop the server for [path] (kills the process tree).
  Future<void> stop(String path) async {
    if (!_processes.containsKey(path)) return;
    // Mark stopped *before* teardown so the exitCode handler ([_onExit]) sees
    // the user-initiated stop and skips logging a spurious "exited" line.
    _setState(
      path,
      _stateFor(path).copyWith(
        status: OdooServerStatus.stopped,
        pid: () => null,
      ),
    );
    await _teardown(path);
    _appendLog(path, '');
    _appendLog(path, '[-] Server stopped.');
  }

  /// Whether a live process is currently tracked for [path].
  bool isRunning(String path) => _processes.containsKey(path);

  /// Clear the accumulated log lines for [path] (keeps status/pid).
  void clearLogs(String path) {
    _setState(path, _stateFor(path).copyWith(logs: const []));
  }

  void _onExit(String path, int code) {
    _cancelSubs(path);
    _processes.remove(path);
    final cur = _stateFor(path);
    // Preserve an explicit "stopped" (user action) over "exited".
    if (cur.status == OdooServerStatus.stopped) return;
    _appendLog(path, '');
    _appendLog(path, '[-] Odoo process exited (code $code).');
    _setState(
      path,
      cur.copyWith(
        status:
            code == 0 ? OdooServerStatus.stopped : OdooServerStatus.error,
        pid: () => null,
      ),
    );
  }

  /// Kill the process + cancel its stream subscriptions (no state change).
  Future<void> _teardown(String path) async {
    _cancelSubs(path);
    final process = _processes.remove(path);
    if (process != null) {
      await OdooServerService.killTree(process);
    }
  }

  void _cancelSubs(String path) {
    final subs = _subs.remove(path);
    if (subs == null) return;
    for (final s in subs) {
      s.cancel();
    }
  }

}

/// True when [line] indicates Odoo's HTTP service is up and serving.
///
/// Matches lines like `HTTP service (werkzeug) running on HOST:PORT`. Odoo
/// logs this to stderr once the server is ready to accept requests.
bool isOdooHttpReadyLine(String line) {
  final l = line.toLowerCase();
  if (l.contains('http service') && l.contains('running')) return true;
  return RegExp(r'running on \S+:\d+').hasMatch(l);
}

final runningServersProvider =
    NotifierProvider<RunningServersNotifier, Map<String, OdooServerState>>(
        RunningServersNotifier.new);
