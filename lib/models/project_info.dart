class ProjectInfo {
  final String name;
  final String path;
  final String profileName;
  final int httpPort;
  final int longpollingPort;
  final String createdAt;

  const ProjectInfo({
    required this.name,
    required this.path,
    required this.profileName,
    required this.httpPort,
    required this.longpollingPort,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'profileName': profileName,
        'httpPort': httpPort,
        'longpollingPort': longpollingPort,
        'createdAt': createdAt,
      };

  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        profileName: (json['profileName'] ?? '').toString(),
        httpPort: json['httpPort'] as int? ?? 8069,
        longpollingPort: json['longpollingPort'] as int? ?? 8072,
        createdAt: (json['createdAt'] ?? '').toString(),
      );
}
