import 'dart:io' show Platform;

class PlatformService {
  static bool get isLinux => Platform.isLinux;
  static bool get isWindows => Platform.isWindows;

  static List<String> get pythonCandidates {
    if (isWindows) {
      return ['python', 'python3', 'py'];
    }
    return ['python3', 'python'];
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
