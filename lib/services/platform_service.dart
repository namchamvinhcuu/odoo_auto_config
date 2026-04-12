import 'dart:io'
    show Directory, File, Link, Platform, Process, ProcessResult;

class PlatformService {
  /// Run a PowerShell script file with -STA flag (required for WinForms dialogs).
  static Future<String?> _runPsScript(String script) async {
    final tempDir = Platform.environment['TEMP'] ?? r'C:\Windows\Temp';
    final scriptFile = File('$tempDir\\odoo_auto_config_dialog.ps1');
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
      ], runInShell: true);

      final path = result.stdout.toString().trim();
      if (path.isNotEmpty && result.exitCode == 0) return path;
      return null;
    } finally {
      try {
        await scriptFile.delete();
      } catch (_) {}
    }
  }

  /// Pick a directory using modern Windows dialog.
  /// On other platforms, returns null (caller should use file_picker).
  static Future<String?> pickDirectory({String? dialogTitle}) async {
    if (!isWindows) return null;

    final title = dialogTitle ?? 'Select Folder';
    return _runPsScript('''
\$source = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
class FileOpenDialogCls { }

[ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IFileOpenDialog {
    [PreserveSig] int Show(IntPtr hwnd);
    void SetFileTypes();
    void SetFileTypeIndex();
    void GetFileTypeIndex();
    void Advise();
    void Unadvise();
    void SetOptions(uint fos);
    void GetOptions(out uint fos);
    void SetDefaultFolder(IShellItem psi);
    void SetFolder(IShellItem psi);
    void GetFolder(out IShellItem ppsi);
    void GetCurrentSelection(out IShellItem ppsi);
    void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetFileName();
    void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
    void SetOkButtonLabel();
    void SetFileNameLabel();
    void GetResult(out IShellItem ppsi);
    void AddPlace();
    void SetDefaultExtension();
    void Close();
    void SetClientGuid();
    void ClearClientData();
    void SetFilter();
    void GetResults();
    void GetSelectedItems();
}

[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IShellItem {
    void BindToHandler();
    void GetParent();
    void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
    void GetAttributes();
    void Compare();
}

public class FolderPicker {
    public static string Show(string title) {
        var dialog = (IFileOpenDialog)new FileOpenDialogCls();
        dialog.SetOptions(0x20); // FOS_PICKFOLDERS
        dialog.SetTitle(title);
        int hr = dialog.Show(IntPtr.Zero);
        if (hr != 0) return null;
        IShellItem item;
        dialog.GetResult(out item);
        string path;
        item.GetDisplayName(0x80058000, out path);
        return path;
    }
}
"@
Add-Type -TypeDefinition \$source -ReferencedAssemblies System.Windows.Forms
\$result = [FolderPicker]::Show("$title")
if (\$result) { Write-Output \$result }
''');
  }

  /// Pick a file using native dialog.
  /// On Windows, uses PowerShell to avoid MSIX/COM crash.
  static Future<String?> pickFile({String? dialogTitle, String? filter}) async {
    if (!isWindows) return null;

    final title = dialogTitle ?? 'Select File';
    final filterStr = filter ?? 'All files (*.*)|*.*';
    return _runPsScript('''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = "$title"
\$dialog.Filter = "$filterStr"
\$result = \$dialog.ShowDialog()
if (\$result -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''');
  }

  static bool get isLinux => Platform.isLinux;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;

  /// Linux package manager: 'apt' (Debian/Ubuntu) or 'dnf' (Fedora/RHEL).
  /// Returns null if neither is found.
  static String? _linuxPm;
  static bool _linuxPmDetected = false;

  static String? get linuxPackageManager {
    if (!isLinux) return null;
    if (!_linuxPmDetected) {
      _linuxPmDetected = true;
      if (File('/usr/bin/apt').existsSync()) {
        _linuxPm = 'apt';
      } else if (File('/usr/bin/dnf').existsSync()) {
        _linuxPm = 'dnf';
      }
    }
    return _linuxPm;
  }

  static bool get isApt => linuxPackageManager == 'apt';
  static bool get isDnf => linuxPackageManager == 'dnf';

  static List<String> get pythonCandidates {
    if (isWindows) {
      final candidates = <String>['python', 'python3', 'py'];
      final userProfile =
          Platform.environment['USERPROFILE'] ?? r'C:\Users\Default';
      final wellKnownDirs = <String>[
        '$userProfile\\AppData\\Local\\Programs\\Python',
        r'C:\Python',
        r'C:\Program Files\Python',
        r'C:\Program Files (x86)\Python',
        // Microsoft Store Python
        '$userProfile\\AppData\\Local\\Microsoft\\WindowsApps',
        // Scoop
        '$userProfile\\scoop\\apps\\python\\current',
        // Chocolatey
        r'C:\tools\python',
        // Conda / Miniconda / Anaconda
        '$userProfile\\miniconda3',
        '$userProfile\\anaconda3',
        r'C:\ProgramData\miniconda3',
        r'C:\ProgramData\anaconda3',
        // pyenv-win
        '$userProfile\\.pyenv\\pyenv-win\\versions',
      ];

      for (final dir in wellKnownDirs) {
        final d = Directory(dir);
        if (!d.existsSync()) continue;
        try {
          // Check if python.exe exists directly in this directory
          if (File('$dir\\python.exe').existsSync()) {
            candidates.add('$dir\\python.exe');
          }
          // Scan subdirectories (e.g. Python311, Python312)
          for (final entry in d.listSync()) {
            if (entry is Directory) {
              final exe = File('${entry.path}\\python.exe');
              if (exe.existsSync()) {
                candidates.add(exe.path);
              }
            }
          }
        } catch (_) {}
      }

      return candidates;
    }
    // On macOS GUI apps don't inherit the user's shell PATH,
    // so we must also probe well-known absolute paths.
    final candidates = <String>['python3', 'python'];
    final home = Platform.environment['HOME'] ?? '';
    if (isMacOS) {
      candidates.addAll([
        '/opt/homebrew/bin/python3',
        '/usr/local/bin/python3',
        '/usr/bin/python3',
      ]);
      // Discover versioned python binaries (e.g. python3.11, python3.12)
      for (final dir in ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin']) {
        try {
          for (final entry in Directory(dir).listSync()) {
            if (entry is File || entry is Link) {
              final name = entry.path.split('/').last;
              if (RegExp(r'^python3\.\d+$').hasMatch(name)) {
                candidates.add(entry.path);
              }
            }
          }
        } catch (_) {}
      }
    } else if (isLinux) {
      candidates.addAll(['/usr/local/bin/python3', '/usr/bin/python3']);
      // Discover versioned python binaries (e.g. python3.11, python3.12)
      for (final dir in ['/usr/bin', '/usr/local/bin']) {
        try {
          for (final entry in Directory(dir).listSync()) {
            if (entry is File) {
              final name = entry.path.split('/').last;
              if (RegExp(r'^python3\.\d+$').hasMatch(name)) {
                candidates.add(entry.path);
              }
            }
          }
        } catch (_) {}
      }
    }
    // Discover pyenv-installed versions directly (shims don't work in GUI apps)
    if ((isMacOS || isLinux) && home.isNotEmpty) {
      final versionsDir = Directory('$home/.pyenv/versions');
      if (versionsDir.existsSync()) {
        try {
          for (final entry in versionsDir.listSync()) {
            if (entry is Directory) {
              candidates.add('${entry.path}/bin/python3');
            }
          }
        } catch (_) {}
      }
    }
    return candidates;
  }

  /// Resolve brew binary path (macOS GUI apps don't have PATH from shell)
  static Future<String> get brewPath async {
    if (!isMacOS) return 'brew';
    final candidates = [
      '/opt/homebrew/bin/brew',
      '/usr/local/bin/brew',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return 'brew';
  }

  /// Resolve docker binary path (macOS GUI apps don't have PATH from shell)
  static Future<String> get dockerPath async {
    if (!isMacOS) return 'docker';

    // Check common docker binary locations on macOS
    final candidates = [
      '/usr/local/bin/docker',
      '/opt/homebrew/bin/docker',
      '${Platform.environment['HOME']}/.orbstack/bin/docker',
      '/Applications/Docker.app/Contents/Resources/bin/docker',
      '/Applications/OrbStack.app/Contents/MacOS/xbin/docker',
    ];

    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return 'docker'; // fallback
  }

  static Future<String> get mkcertPath async {
    if (isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final candidates = [
        '$localAppData\\Microsoft\\WinGet\\Links\\mkcert.exe',
        '$localAppData\\Microsoft\\WinGet\\Packages\\FiloSottile.mkcert_Microsoft.Winget.Source_8wekyb3d8bbwe\\mkcert.exe',
        'C:\\Program Files\\mkcert\\mkcert.exe',
        'C:\\ProgramData\\chocolatey\\bin\\mkcert.exe',
      ];
      for (final path in candidates) {
        if (await File(path).exists()) return path;
      }
    } else if (isMacOS) {
      final candidates = [
        '/opt/homebrew/bin/mkcert',
        '/usr/local/bin/mkcert',
      ];
      for (final path in candidates) {
        if (await File(path).exists()) return path;
      }
    }
    return 'mkcert'; // fallback: rely on PATH
  }

  static Future<String> get ghPath async {
    if (isMacOS) {
      final candidates = [
        '/opt/homebrew/bin/gh',
        '/usr/local/bin/gh',
      ];
      for (final path in candidates) {
        if (await File(path).exists()) return path;
      }
    } else if (isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final candidates = [
        '$localAppData\\Microsoft\\WinGet\\Links\\gh.exe',
        '$programFiles\\GitHub CLI\\gh.exe',
        '$localAppData\\Programs\\gh\\bin\\gh.exe',
      ];
      for (final path in candidates) {
        if (await File(path).exists()) return path;
      }
      // Fallback: use where.exe to find gh in PATH
      try {
        final where = await Process.run(
          'where.exe', ['gh'],
          runInShell: true,
        );
        if (where.exitCode == 0) {
          final found = (where.stdout as String).trim().split('\n').first.trim();
          if (found.isNotEmpty) return found;
        }
      } catch (_) {}
    } else {
      // Linux
      final candidates = [
        '/usr/bin/gh',
        '/usr/local/bin/gh',
        '/snap/bin/gh',
      ];
      for (final path in candidates) {
        if (await File(path).exists()) return path;
      }
    }
    return 'gh';
  }

  static Future<bool> isGhInstalled() async {
    try {
      final result = await runGh(['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Run a gh command (Process.run). Handles Windows path-with-spaces issue.
  static Future<ProcessResult> runGh(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final gh = await ghPath;
    if (isWindows && gh.contains(' ')) {
      // On Windows, runInShell uses cmd /c which splits at spaces.
      // Pass full path without runInShell — CreateProcess handles spaces.
      return Process.run(gh, args,
          workingDirectory: workingDirectory, environment: environment);
    }
    return Process.run(gh, args,
        workingDirectory: workingDirectory,
        runInShell: true,
        environment: environment);
  }

  /// Start a gh process (Process.start) for streaming output.
  /// Handles Windows path-with-spaces issue.
  static Future<Process> startGh(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final gh = await ghPath;
    if (isWindows && gh.contains(' ')) {
      // On Windows, runInShell uses cmd /c which splits at spaces.
      // Pass full path without runInShell — CreateProcess handles spaces.
      return Process.start(gh, args,
          workingDirectory: workingDirectory, environment: environment);
    }
    return Process.start(gh, args,
        workingDirectory: workingDirectory,
        runInShell: true,
        environment: environment);
  }

  /// Install GitHub CLI (gh) via brew/winget/apt.
  /// Returns exit code (0 = success).
  static Future<int> installGh(void Function(String) log) async {
    final String cmd;
    final List<String> args;

    if (isMacOS) {
      cmd = '/opt/homebrew/bin/brew';
      args = ['install', 'gh'];
      // Fallback if homebrew is in /usr/local
      if (!await File(cmd).exists()) {
        final altBrew = '/usr/local/bin/brew';
        if (await File(altBrew).exists()) {
          log('[+] Installing gh via brew...');
          final result = await Process.run(altBrew, args, runInShell: true);
          log(result.stdout.toString());
          if (result.exitCode != 0) log(result.stderr.toString());
          return result.exitCode;
        }
      }
    } else if (isWindows) {
      cmd = 'winget';
      args = ['install', '--id', 'GitHub.cli', '-e', '--accept-source-agreements'];
    } else if (isDnf) {
      cmd = 'pkexec';
      args = [
        'bash', '-c',
        "dnf install -y 'dnf-command(config-manager)' && "
            'dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && '
            'dnf install -y gh',
      ];
    } else {
      cmd = 'pkexec';
      args = ['apt', 'install', '-y', 'gh'];
    }

    log('[+] Installing gh...');
    try {
      final result = await Process.run(cmd, args, runInShell: true);
      final output = result.stdout.toString().trim();
      final error = result.stderr.toString().trim();
      if (output.isNotEmpty) log(output);
      if (result.exitCode != 0 && error.isNotEmpty) log('[ERROR] $error');
      return result.exitCode;
    } catch (e) {
      log('[ERROR] $e');
      return 1;
    }
  }

  /// Check if VSCode is installed
  static Future<bool> isVscodeInstalled() async {
    try {
      if (isMacOS) {
        final result = await Process.run(
            'mdfind', ['kMDItemCFBundleIdentifier == "com.microsoft.VSCode"'],
            runInShell: true);
        return result.exitCode == 0 &&
            result.stdout.toString().trim().isNotEmpty;
      } else if (isWindows) {
        final result =
            await Process.run('cmd', ['/c', 'where', 'code'], runInShell: true);
        return result.exitCode == 0;
      } else {
        final result =
            await Process.run('which', ['code'], runInShell: true);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  /// Install command for VSCode
  static ({String executable, List<String> args, String description})
      vscodeInstallCommand() {
    if (isWindows) {
      return (
        executable: 'winget',
        args: [
          'install',
          'Microsoft.VisualStudioCode',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ],
        description: 'winget install Microsoft.VisualStudioCode',
      );
    } else if (isMacOS) {
      return (
        executable: 'brew',
        args: ['install', '--cask', 'visual-studio-code'],
        description: 'brew install --cask visual-studio-code',
      );
    } else if (isDnf) {
      return (
        executable: 'pkexec',
        args: [
          'bash', '-c',
          'rpm --import https://packages.microsoft.com/keys/microsoft.asc && '
          'echo -e "[code]\\nname=Visual Studio Code\\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\\nenabled=1\\ngpgcheck=1\\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo && '
          'dnf install -y code',
        ],
        description: 'dnf install code (Microsoft repository)',
      );
    } else {
      return (
        executable: 'pkexec',
        args: [
          'bash', '-c',
          'apt update && apt install -y wget gpg && '
          'wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/ms.gpg && '
          'install -D -o root -g root -m 644 /tmp/ms.gpg /usr/share/keyrings/microsoft-archive-keyring.gpg && '
          'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list && '
          'apt update && apt install -y code',
        ],
        description: 'apt install code (Microsoft repository)',
      );
    }
  }

  static String venvActivateScript(String venvPath) {
    if (isWindows) {
      return '$venvPath\\Scripts\\activate.bat';
    }
    return '$venvPath/bin/activate';
  }

  static String venvPython(String venvPath) {
    if (isWindows) {
      return '$venvPath\\Scripts\\python.exe';
    }
    return '$venvPath/bin/python';
  }

  static String venvPip(String venvPath) {
    if (isWindows) {
      return '$venvPath\\Scripts\\pip.exe';
    }
    return '$venvPath/bin/pip';
  }
}
