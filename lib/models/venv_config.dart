import 'package:path/path.dart' as p;

class VenvConfig {
  final String pythonPath;
  final String targetDirectory;
  final String venvName;

  const VenvConfig({
    required this.pythonPath,
    required this.targetDirectory,
    this.venvName = 'venv',
  });

  String get fullPath => p.join(targetDirectory, venvName);
}
