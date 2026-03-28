class WorkspaceInfo {
  final String name;
  final String path;
  final String type;
  final String description;
  final String createdAt;

  const WorkspaceInfo({
    required this.name,
    required this.path,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        'description': description,
        'createdAt': createdAt,
      };

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? '').toString(),
      );
}
