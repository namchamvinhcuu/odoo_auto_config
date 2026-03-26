class PythonInfo {
  final String executablePath;
  final String version;
  final bool hasPip;
  final String pipVersion;
  final bool hasVenv;

  const PythonInfo({
    required this.executablePath,
    required this.version,
    required this.hasPip,
    this.pipVersion = '',
    required this.hasVenv,
  });
}
