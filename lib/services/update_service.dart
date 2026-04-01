import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../generated/version.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String? downloadUrl;
  final String? releaseUrl;
  final String? assetName;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    this.downloadUrl,
    this.releaseUrl,
    this.assetName,
  });

  bool get hasUpdate =>
      _compareVersions(latestVersion, currentVersion) > 0;
}

class UpdateService {
  static const _repo = 'namchamvinhcuu/workspace-configuration';
  static const _apiUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  /// App version from compiled Dart const (lib/generated/version.dart)
  static String getCurrentVersion() => appVersion;

  /// Check GitHub for latest release
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final currentVersion = getCurrentVersion();
      final result = await Process.run('curl', [
        '-sL',
        '-H', 'Accept: application/vnd.github.v3+json',
        _apiUrl,
      ], runInShell: true);

      if (result.exitCode != 0) return null;

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final tagName = (json['tag_name'] ?? '').toString().replaceFirst('v', '');
      final assets = json['assets'] as List? ?? [];
      final releaseUrl = (json['html_url'] ?? '').toString();

      // Find correct asset for current platform
      final suffix = _platformAssetSuffix();
      String? downloadUrl;
      String? assetName;
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString();
        if (name.endsWith(suffix)) {
          downloadUrl = (asset['browser_download_url'] ?? '').toString();
          assetName = name;
          break;
        }
      }

      return UpdateInfo(
        latestVersion: tagName,
        currentVersion: currentVersion,
        downloadUrl: downloadUrl,
        releaseUrl: releaseUrl,
        assetName: assetName,
      );
    } catch (_) {
      return null;
    }
  }

  /// Download update and return path to downloaded file
  static Future<String?> download(
    String url,
    String fileName, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final downloadDir = _getDownloadDir();
      final filePath = p.join(downloadDir, fileName);

      // Use curl with progress
      final result = await Process.run('curl', [
        '-fSL',
        '-o', filePath,
        url,
      ], runInShell: true);

      if (result.exitCode != 0) return null;

      // Remove quarantine on macOS (prevents Gatekeeper blocking)
      if (Platform.isMacOS) {
        await Process.run('xattr', ['-d', 'com.apple.quarantine', filePath],
            runInShell: true);
      }

      // Make executable on Linux
      if (Platform.isLinux && fileName.endsWith('.AppImage')) {
        await Process.run('chmod', ['+x', filePath]);
      }

      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// Install the downloaded update
  static Future<bool> install(String filePath) async {
    try {
      if (Platform.isLinux) {
        return _installLinux(filePath);
      } else if (Platform.isMacOS) {
        return _installMacOS(filePath);
      } else if (Platform.isWindows) {
        return _installWindows(filePath);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Linux: replace AppImage ──

  static Future<bool> _installLinux(String newAppImage) async {
    // The actual AppImage path is tracked via APPIMAGE env var
    final appImagePath = Platform.environment['APPIMAGE'];
    if (appImagePath == null || appImagePath.isEmpty) {
      // Not running as AppImage - just open file manager to downloaded file
      await Process.run('xdg-open', [p.dirname(newAppImage)]);
      return false;
    }

    // Create update script that waits for app to exit, replaces, and relaunches
    final scriptPath = p.join(Directory.systemTemp.path, 'wsc_update.sh');
    await File(scriptPath).writeAsString('''#!/bin/bash
# Wait for current process to exit
while kill -0 \$1 2>/dev/null; do sleep 0.5; done
# Replace AppImage
cp "$newAppImage" "$appImagePath"
chmod +x "$appImagePath"
rm "$newAppImage"
# Relaunch
exec "$appImagePath" &
rm "\$0"
''');
    await Process.run('chmod', ['+x', scriptPath]);

    // Run script in background with current PID
    await Process.start('bash', [scriptPath, '$pid'],
        mode: ProcessStartMode.detached);

    // Exit app so script can replace the file
    exit(0);
  }

  // ── macOS: mount DMG and copy .app ──

  static Future<bool> _installMacOS(String dmgPath) async {
    // Remove quarantine from DMG before mounting (prevents Gatekeeper)
    await Process.run('xattr', ['-d', 'com.apple.quarantine', dmgPath],
        runInShell: true);

    // Mount DMG
    final mountResult = await Process.run('hdiutil', [
      'attach', dmgPath, '-nobrowse', '-quiet',
    ]);
    if (mountResult.exitCode != 0) return false;

    // Find mount point
    final mountOutput = mountResult.stdout.toString();
    final mountPoint = RegExp(r'/Volumes/[^\n]+')
        .firstMatch(mountOutput)
        ?.group(0)
        ?.trim();
    if (mountPoint == null) return false;

    // Find .app in mounted volume
    final appDir = Directory(mountPoint);
    String? appPath;
    await for (final entity in appDir.list()) {
      if (entity.path.endsWith('.app')) {
        appPath = entity.path;
        break;
      }
    }
    if (appPath == null) {
      await Process.run('hdiutil', ['detach', mountPoint, '-quiet']);
      return false;
    }

    final appName = p.basename(appPath);
    final destPath = '/Applications/$appName';

    // Create update script
    final scriptPath =
        p.join(Directory.systemTemp.path, 'wsc_update.sh');
    await File(scriptPath).writeAsString('''#!/bin/bash
while kill -0 \$1 2>/dev/null; do sleep 0.5; done
rm -rf "$destPath"
cp -R "$appPath" "$destPath"
xattr -cr "$destPath"
codesign --force --deep --sign - "$destPath"
hdiutil detach "$mountPoint" -quiet
rm "$dmgPath"
open "$destPath"
rm "\$0"
''');
    await Process.run('chmod', ['+x', scriptPath]);

    await Process.start('bash', [scriptPath, '$pid'],
        mode: ProcessStartMode.detached);

    exit(0);
  }

  // ── Windows: run MSIX installer ──

  static Future<bool> _installWindows(String msixPath) async {
    // MSIX can be installed by simply running it, or via PowerShell
    await Process.start('cmd', ['/c', 'start', '', msixPath],
        mode: ProcessStartMode.detached);
    exit(0);
  }

  // ── Helpers ──

  static String _platformAssetSuffix() {
    if (Platform.isLinux) return '.AppImage';
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isWindows) return '.msix';
    return '';
  }

  static String _getDownloadDir() {
    if (Platform.isWindows) {
      return p.join(Platform.environment['USERPROFILE'] ?? '', 'Downloads');
    }
    return p.join(Platform.environment['HOME'] ?? '/tmp', 'Downloads');
  }
}

/// Compare two semver strings. Returns >0 if a > b, 0 if equal, <0 if a < b
int _compareVersions(String a, String b) {
  final partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final len = partsA.length > partsB.length ? partsA.length : partsB.length;
  for (var i = 0; i < len; i++) {
    final va = i < partsA.length ? partsA[i] : 0;
    final vb = i < partsB.length ? partsB[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}
