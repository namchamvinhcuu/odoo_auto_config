import 'package:path/path.dart' as p;

class FolderStructureConfig {
  final String baseDirectory;
  final String projectName;
  final String odooSourcePath;
  final int odooVersion;
  final bool createAddons;
  final bool createThirdPartyAddons;
  final bool createConfigDir;
  final bool createVenvDir;

  const FolderStructureConfig({
    required this.baseDirectory,
    required this.projectName,
    this.odooSourcePath = '',
    this.odooVersion = 17,
    this.createAddons = true,
    this.createThirdPartyAddons = true,
    this.createConfigDir = true,
    this.createVenvDir = true,
  });

  String get projectPath => p.join(baseDirectory, projectName);
}
