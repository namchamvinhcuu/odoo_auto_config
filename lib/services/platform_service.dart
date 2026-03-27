import 'dart:io' show Directory, File, Link, Platform, Process;

class PlatformService {
  /// Run a PowerShell script file with -STA flag (required for WinForms dialogs).
  static Future<String?> _runPsScript(String script) async {
    final tempDir = Platform.environment['TEMP'] ?? r'C:\Windows\Temp';
    final scriptFile = File('$tempDir\\odoo_auto_config_dialog.ps1');
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
        runInShell: true,
      );

      final path = result.stdout.toString().trim();
      if (path.isNotEmpty && result.exitCode == 0) return path;
      return null;
    } finally {
      try { await scriptFile.delete(); } catch (_) {}
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

  static List<String> get pythonCandidates {
    if (isWindows) {
      final candidates = <String>['python', 'python3', 'py'];
      final userProfile = Platform.environment['USERPROFILE'] ?? r'C:\Users\Default';
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
      candidates.addAll([
        '/usr/local/bin/python3',
        '/usr/bin/python3',
      ]);
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
