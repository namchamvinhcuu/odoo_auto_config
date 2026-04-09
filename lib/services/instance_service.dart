import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Manages multi-instance lifecycle: registry, IPC signals, and launching.
///
/// Directory: `~/.config/odoo_auto_config/instances/`
///   `{pid}.json`   — instance registry (pid, label, started)
///   `.tray.lock`   — exclusive lock held by tray owner
///   `{pid}.show`   — signal: show that instance's window
///   `.quit_all`    — signal: all instances exit
class InstanceService {
  static String get _instancesDir {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, '.config', 'odoo_auto_config', 'instances');
  }

  static int get _myPid => pid;

  static bool _isTrayOwner = false;
  static StreamSubscription<FileSystemEvent>? _dirWatcher;

  /// Whether this instance owns the tray icon.
  static bool get isTrayOwner => _isTrayOwner;

  // ── Registry ──

  /// Register this instance in the instances directory.
  static Future<void> register({String? label}) async {
    final dir = Directory(_instancesDir);
    await dir.create(recursive: true);
    final file = File(p.join(_instancesDir, '$_myPid.json'));
    await file.writeAsString(jsonEncode({
      'pid': _myPid,
      'label': label ?? 'Instance',
      'started': DateTime.now().toIso8601String(),
    }));
  }

  /// Unregister this instance (delete registry file).
  static Future<void> unregister() async {
    final file = File(p.join(_instancesDir, '$_myPid.json'));
    if (await file.exists()) await file.delete();
  }

  /// Update this instance's label (shown in tray menu).
  /// Call when user navigates to a specific project or switches tabs.
  static Future<void> updateLabel(String label) async {
    final file = File(p.join(_instancesDir, '$_myPid.json'));
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data['label'] = label;
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  /// List all alive instances, cleaning up stale entries.
  /// Handles duplicate labels by appending (1), (2), etc.
  static Future<List<Map<String, dynamic>>> listInstances() async {
    final dir = Directory(_instancesDir);
    if (!await dir.exists()) return [];
    final instances = <Map<String, dynamic>>[];
    final pidPattern = RegExp(r'^\d+\.json$');

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!pidPattern.hasMatch(name)) continue;
      try {
        final content = await entity.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final instPid = data['pid'] as int;
        if (await _isProcessAlive(instPid)) {
          instances.add(data);
        } else {
          await entity.delete();
        }
      } catch (_) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    // Sort by started time for consistent ordering
    instances.sort((a, b) =>
        (a['started'] as String).compareTo(b['started'] as String));

    // Handle duplicate labels: append (1), (2), ...
    final labelCount = <String, int>{};
    for (final inst in instances) {
      final label = inst['label'] as String;
      labelCount[label] = (labelCount[label] ?? 0) + 1;
    }
    final labelIndex = <String, int>{};
    for (final inst in instances) {
      final label = inst['label'] as String;
      if (labelCount[label]! > 1) {
        labelIndex[label] = (labelIndex[label] ?? 0) + 1;
        inst['displayLabel'] = '$label (${labelIndex[label]})';
      } else {
        inst['displayLabel'] = label;
      }
    }

    return instances;
  }

  // ── Tray ownership ──

  /// Try to acquire tray ownership via PID file.
  /// Checks if another living process already owns the tray.
  /// Returns true if this instance is now the tray owner.
  static Future<bool> tryAcquireTrayOwnership() async {
    final lockFile = File(p.join(_instancesDir, '.tray.lock'));
    await lockFile.parent.create(recursive: true);

    // Check if another living process owns the tray
    if (await lockFile.exists()) {
      try {
        final content = (await lockFile.readAsString()).trim();
        final ownerPid = int.tryParse(content);
        if (ownerPid != null && ownerPid != _myPid) {
          if (await _isProcessAlive(ownerPid)) {
            _isTrayOwner = false;
            return false;
          }
        }
      } catch (_) {
        // Can't read file, try to take ownership
      }
    }

    // Take ownership by writing our PID
    await lockFile.writeAsString('$_myPid');
    _isTrayOwner = true;
    return true;
  }

  // ── IPC Signals ──

  /// Signal a specific instance to show its window.
  static Future<void> signalShow(int targetPid) async {
    final file = File(p.join(_instancesDir, '$targetPid.show'));
    await file.writeAsString('show');
  }

  /// Signal all instances to quit.
  static Future<void> signalQuitAll() async {
    final file = File(p.join(_instancesDir, '.quit_all'));
    await file.writeAsString('quit');
  }

  /// Start watching the instances directory for signals.
  /// [onShow] called when this instance should show its window.
  /// [onQuitAll] called when all instances should exit.
  /// [onInstancesChanged] called when instance list changes (for tray menu rebuild).
  static void startWatching({
    required Future<void> Function() onShow,
    required Future<void> Function() onQuitAll,
    Future<void> Function()? onInstancesChanged,
  }) {
    final dir = Directory(_instancesDir);
    _dirWatcher = dir.watch().listen((event) {
      final name = p.basename(event.path);

      // Show signal for this instance
      if (name == '$_myPid.show' &&
          (event.type == FileSystemEvent.create ||
              event.type == FileSystemEvent.modify)) {
        onShow();
        // Clean up signal file
        File(event.path).delete().ignore();
      }

      // Quit all signal
      if (name == '.quit_all' &&
          (event.type == FileSystemEvent.create ||
              event.type == FileSystemEvent.modify)) {
        onQuitAll();
      }

      // Instance list changed (for tray owner to rebuild menu)
      if (_isTrayOwner &&
          name.endsWith('.json') &&
          onInstancesChanged != null) {
        onInstancesChanged();
      }
    });
  }

  /// Stop watching.
  static Future<void> stopWatching() async {
    await _dirWatcher?.cancel();
    _dirWatcher = null;
  }

  // ── Cleanup ──

  /// Full cleanup: unregister, release tray ownership, stop watching.
  static Future<void> cleanup() async {
    await stopWatching();
    await unregister();
    // Release tray ownership (delete PID file so others can take over)
    if (_isTrayOwner) {
      try {
        final lockFile = File(p.join(_instancesDir, '.tray.lock'));
        if (await lockFile.exists()) await lockFile.delete();
      } catch (_) {}
    }
    _isTrayOwner = false;
  }

  // ── Launch new instance ──

  /// Launch a new instance of this app.
  static Future<void> launchNewInstance() async {
    if (Platform.isMacOS) {
      await _launchMacOS();
    } else if (Platform.isWindows) {
      await _launchWindows();
    } else if (Platform.isLinux) {
      await _launchLinux();
    }
  }

  static Future<void> _launchMacOS() async {
    // Run the binary directly with --child-instance flag.
    // AppDelegate detects this flag and sets .accessory activation policy,
    // so the child instance does NOT show a separate Dock icon.
    // (Using `open -n -a` would register a new LaunchServices instance → 2 Dock icons)
    final execPath = Platform.resolvedExecutable;
    await Process.start(
      execPath,
      ['--child-instance'],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
  }

  static Future<void> _launchWindows() async {
    // Try MSIX launch first
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r"$app = Get-AppxPackage | Where-Object { $_.Name -like '*odoo*auto*config*' } | Select-Object -First 1; "
            r"if ($app) { Start-Process ('shell:AppsFolder\' + $app.PackageFamilyName + '!App'); Write-Output 'ok' } "
            r"else { Write-Output 'notfound' }",
      ],
      runInShell: true,
    );
    if ((result.stdout as String).trim() == 'ok') return;

    // Fallback: direct executable (debug mode)
    await Process.start(
      Platform.resolvedExecutable,
      [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
  }

  static Future<void> _launchLinux() async {
    // Only use APPIMAGE env if the actual binary is inside an AppImage mount
    // (AppImageLauncher can inject APPIMAGE env into non-AppImage processes)
    final resolvedExec = Platform.resolvedExecutable;
    final appImagePath = Platform.environment['APPIMAGE'];
    final isReallyAppImage = appImagePath != null &&
        appImagePath.isNotEmpty &&
        resolvedExec.contains('/tmp/.mount_');
    final execPath = isReallyAppImage ? appImagePath : resolvedExec;
    await Process.start(
      execPath,
      [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
  }

  // ── Utilities ──

  /// Check if a process with the given PID is still alive.
  static Future<bool> _isProcessAlive(int targetPid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $targetPid', '/NH'],
          runInShell: true,
        );
        return (result.stdout as String).contains('$targetPid');
      } else {
        // macOS / Linux: kill -0 checks if process exists
        final result = await Process.run(
          'kill',
          ['-0', '$targetPid'],
          runInShell: true,
        );
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }
}
