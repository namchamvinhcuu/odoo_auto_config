class ProjectInfo {
  final String name;
  final String path;
  final String description;
  final int httpPort;
  final int longpollingPort;
  final String createdAt;

  const ProjectInfo({
    required this.name,
    required this.path,
    required this.description,
    required this.httpPort,
    required this.longpollingPort,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'description': description,
        'httpPort': httpPort,
        'longpollingPort': longpollingPort,
        'createdAt': createdAt,
      };

  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        httpPort: json['httpPort'] as int? ?? 8069,
        longpollingPort: json['longpollingPort'] as int? ?? 8072,
        createdAt: (json['createdAt'] ?? '').toString(),
      );
}
