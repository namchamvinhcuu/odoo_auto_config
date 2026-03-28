class WorkspaceInfo {
  final String name;
  final String path;
  final String type;
  final String description;
  final String createdAt;
  final bool favourite;
  final int? port;

  const WorkspaceInfo({
    required this.name,
    required this.path,
    required this.type,
    required this.description,
    required this.createdAt,
    this.favourite = false,
    this.port,
  });

  WorkspaceInfo copyWith({bool? favourite, int? port}) => WorkspaceInfo(
        name: name,
        path: path,
        type: type,
        description: description,
        createdAt: createdAt,
        favourite: favourite ?? this.favourite,
        port: port ?? this.port,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        'description': description,
        'createdAt': createdAt,
        'favourite': favourite,
        'port': port,
      };

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? '').toString(),
        favourite: json['favourite'] as bool? ?? false,
        port: json['port'] as int?,
      );
}
