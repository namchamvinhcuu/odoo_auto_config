class WorkspaceInfo {
  final String name;
  final String path;
  final String type;
  final String description;
  final String createdAt;
  final bool favourite;

  const WorkspaceInfo({
    required this.name,
    required this.path,
    required this.type,
    required this.description,
    required this.createdAt,
    this.favourite = false,
  });

  WorkspaceInfo copyWith({bool? favourite}) => WorkspaceInfo(
        name: name,
        path: path,
        type: type,
        description: description,
        createdAt: createdAt,
        favourite: favourite ?? this.favourite,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        'description': description,
        'createdAt': createdAt,
        'favourite': favourite,
      };

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? '').toString(),
        favourite: json['favourite'] as bool? ?? false,
      );
}
