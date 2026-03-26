class VenvInfo {
  final String path;
  final String pythonVersion;
  final String pipVersion;
  final bool isValid;
  final String label;

  const VenvInfo({
    required this.path,
    required this.pythonVersion,
    this.pipVersion = '',
    required this.isValid,
    this.label = '',
  });

  String get name => label.isNotEmpty
      ? label
      : path.split('/').last.split('\\').last;

  Map<String, dynamic> toJson() => {
        'path': path,
        'pythonVersion': pythonVersion,
        'pipVersion': pipVersion,
        'label': label,
      };

  factory VenvInfo.fromJson(Map<String, dynamic> json) => VenvInfo(
        path: json['path'] as String? ?? '',
        pythonVersion: json['pythonVersion'] as String? ?? '',
        pipVersion: json['pipVersion'] as String? ?? '',
        isValid: true, // Will be re-validated on load
        label: json['label'] as String? ?? '',
      );
}
