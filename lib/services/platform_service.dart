import 'dart:io' show Platform, Directory;

class PlatformService {
  static bool get isLinux => Platform.isLinux;
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;

  static List<String> get pythonCandidates {
    if (isWindows) {
      return ['python', 'python3', 'py'];
    }
    // On macOS GUI apps don't inherit the user's shell PATH,
    // so we must also probe well-known absolute paths.
    final candidates = <String>['python3', 'python'];
    if (isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      final extra = <String>[
        if (home.isNotEmpty) '$home/.pyenv/shims/python3',
        if (home.isNotEmpty) '$home/.pyenv/shims/python',
        '/opt/homebrew/bin/python3',
        '/usr/local/bin/python3',
        '/usr/bin/python3',
      ];
      // Also discover pyenv-installed versions directly
      if (home.isNotEmpty) {
        final versionsDir = Directory('$home/.pyenv/versions');
        if (versionsDir.existsSync()) {
          try {
            for (final entry in versionsDir.listSync()) {
              if (entry is Directory) {
                extra.add('${entry.path}/bin/python3');
              }
            }
          } catch (_) {}
        }
      }
      candidates.addAll(extra);
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
