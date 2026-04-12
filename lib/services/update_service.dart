import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:odoo_auto_config/generated/version.dart';
import 'package:odoo_auto_config/services/instance_service.dart';

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

      // Use curl with timeout (connect 15s, max 5 min for large files)
      final result = await Process.run('curl', [
        '-fSL',
        '--connect-timeout', '15',
        '--max-time', '300',
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
        await Process.run('chmod', ['+x', filePath], runInShell: true);
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
      await Process.run('xdg-open', [p.dirname(newAppImage)], runInShell: true);
      return false;
    }

    // Create update script that waits for app to exit, replaces, and relaunches
    final logPath = p.join(Directory.systemTemp.path, 'wsc_update.log');
    final scriptPath = p.join(Directory.systemTemp.path, 'wsc_update.sh');
    await File(scriptPath).writeAsString('''#!/bin/bash
exec > "$logPath" 2>&1
set -e

# Wait for current process to exit
echo "Waiting for PID \$1 to exit..."
while kill -0 \$1 2>/dev/null; do sleep 0.5; done
echo "App exited."

# Replace AppImage
echo "Copying $newAppImage -> $appImagePath"
cp "$newAppImage" "$appImagePath"
chmod +x "$appImagePath"
rm "$newAppImage"

# Relaunch
echo "Relaunching..."
exec "$appImagePath" &
rm "\$0"
''');
    await Process.run('chmod', ['+x', scriptPath], runInShell: true);

    // Run script in background with current PID
    await Process.start('bash', [scriptPath, '$pid'],
        runInShell: true, mode: ProcessStartMode.detached);

    // Quit all other instances before replacing binary
    await InstanceService.signalQuitAll();
    await Future.delayed(const Duration(seconds: 1));
    exit(0);
  }

  // ── macOS: unzip and replace .app ──

  static Future<bool> _installMacOS(String zipPath) async {
    // Unzip to temp directory
    final tmpDir = p.join(Directory.systemTemp.path, 'wsc_update');
    await Process.run('rm', ['-rf', tmpDir], runInShell: true);
    final unzipResult = await Process.run(
        'ditto', ['-xk', zipPath, tmpDir], runInShell: true);
    if (unzipResult.exitCode != 0) return false;

    // Find .app in unzipped content
    final tmpDirEntity = Directory(tmpDir);
    String? newAppPath;
    await for (final entity in tmpDirEntity.list()) {
      if (entity.path.endsWith('.app')) {
        newAppPath = entity.path;
        break;
      }
    }
    if (newAppPath == null) {
      await Process.run('rm', ['-rf', tmpDir], runInShell: true);
      return false;
    }

    // Detect current .app location from running executable
    // Platform.resolvedExecutable → .../Workspace Configuration.app/Contents/MacOS/odoo_auto_config
    final execPath = Platform.resolvedExecutable;
    final currentAppPath = p.dirname(p.dirname(p.dirname(execPath)));
    final destPath = currentAppPath.endsWith('.app')
        ? currentAppPath
        : p.join('/Applications', p.basename(newAppPath));

    // Create update script
    final logPath = p.join(Directory.systemTemp.path, 'wsc_update.log');
    final scriptPath = p.join(Directory.systemTemp.path, 'wsc_update.sh');
    await File(scriptPath).writeAsString('''#!/bin/bash
exec > "$logPath" 2>&1
set -e

# Wait for current process to exit
while kill -0 \$1 2>/dev/null; do sleep 0.5; done

rm -rf "$destPath"
/usr/bin/ditto "$newAppPath" "$destPath"
xattr -cr "$destPath"

# Cleanup
rm -rf "$tmpDir"
rm -f "$zipPath"

open "$destPath"
rm -f "\$0"
''');
    await Process.run('chmod', ['+x', scriptPath], runInShell: true);

    await Process.start('/bin/bash', [scriptPath, '$pid'],
        runInShell: true, mode: ProcessStartMode.detached);

    // Quit all other instances before replacing binary
    await InstanceService.signalQuitAll();
    await Future.delayed(const Duration(seconds: 1));
    exit(0);
  }

  // ── Windows: update MSIX via PowerShell ──

  static Future<bool> _installWindows(String msixPath) async {
    final scriptPath = p.join(Directory.systemTemp.path, 'wsc_update.ps1');
    final logPath = p.join(Directory.systemTemp.path, 'wsc_update.log');
    final currentPid = pid;
    final script = '''
Start-Transcript -Path "$logPath" -Force

# Wait for app to exit (like macOS/Linux)
Write-Host "Waiting for PID $currentPid to exit..."
do { Start-Sleep -Milliseconds 500 } while (Get-Process -Id $currentPid -ErrorAction SilentlyContinue)
Write-Host "App exited."

# Install MSIX
Write-Host "Installing MSIX: $msixPath"
try {
    Add-AppPackage -Path "$msixPath" -ForceApplicationShutdown -ForceUpdateFromAnyVersion -ErrorAction Stop
    Write-Host "Install complete."
} catch {
    Write-Host "Install error: \$_"
    Stop-Transcript
    exit 1
}

Start-Sleep -Seconds 1

# Relaunch — use direct exe path (shell:AppsFolder fails in detached context)
\$app = Get-AppxPackage | Where-Object { \$_.Name -like '*odoo*auto*config*' } | Select-Object -First 1
if (\$app) {
    Write-Host "Package: \$(\$app.PackageFamilyName)"
    Write-Host "Location: \$(\$app.InstallLocation)"
    \$exe = Get-ChildItem (Join-Path \$app.InstallLocation '*.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
    if (\$exe) {
        Write-Host "Launching: \$(\$exe.FullName)"
        Start-Process \$exe.FullName
    } else {
        Write-Host "ERROR: exe not found in InstallLocation"
    }
} else {
    Write-Host "ERROR: Package not found after install"
}

# Cleanup
Remove-Item -Path "$msixPath" -Force -ErrorAction SilentlyContinue
Stop-Transcript
Remove-Item -Path "$scriptPath" -Force -ErrorAction SilentlyContinue
''';
    await File(scriptPath).writeAsString(script);
    await Process.start(
      'powershell',
      ['-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );

    // Quit all other instances before replacing binary
    await InstanceService.signalQuitAll();
    await Future.delayed(const Duration(seconds: 1));
    exit(0);
  }

  // ── Helpers ──

  static String _platformAssetSuffix() {
    if (Platform.isLinux) return '.AppImage';
    if (Platform.isMacOS) return '-macOS.zip';
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
