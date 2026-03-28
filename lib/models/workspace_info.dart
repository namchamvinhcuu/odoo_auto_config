class WorkspaceInfo {
  final String name;
  final String path;
  final String type;
  final String description;
  final String createdAt;
  final bool favourite;
  final int? port;
  final String? nginxSubdomain;

  const WorkspaceInfo({
    required this.name,
    required this.path,
    required this.type,
    required this.description,
    required this.createdAt,
    this.favourite = false,
    this.port,
    this.nginxSubdomain,
  });

  bool get hasNginx => nginxSubdomain != null && nginxSubdomain!.isNotEmpty;

  WorkspaceInfo copyWith({
    bool? favourite,
    int? port,
    String? Function()? nginxSubdomain,
  }) =>
      WorkspaceInfo(
        name: name,
        path: path,
        type: type,
        description: description,
        createdAt: createdAt,
        favourite: favourite ?? this.favourite,
        port: port ?? this.port,
        nginxSubdomain: nginxSubdomain != null
            ? nginxSubdomain()
            : this.nginxSubdomain,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        'description': description,
        'createdAt': createdAt,
        'favourite': favourite,
        'port': port,
        'nginxSubdomain': nginxSubdomain,
      };

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        createdAt: (json['createdAt'] ?? '').toString(),
        favourite: json['favourite'] as bool? ?? false,
        port: json['port'] as int?,
        nginxSubdomain: json['nginxSubdomain'] as String?,
      );
}
