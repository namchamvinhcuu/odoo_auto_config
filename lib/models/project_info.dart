class ProjectInfo {
  final String name;
  final String path;
  final String description;
  final int httpPort;
  final int longpollingPort;
  final String createdAt;
  final bool favourite;

  const ProjectInfo({
    required this.name,
    required this.path,
    required this.description,
    required this.httpPort,
    required this.longpollingPort,
    required this.createdAt,
    this.favourite = false,
  });

  ProjectInfo copyWith({bool? favourite}) => ProjectInfo(
        name: name,
        path: path,
        description: description,
        httpPort: httpPort,
        longpollingPort: longpollingPort,
        createdAt: createdAt,
        favourite: favourite ?? this.favourite,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'description': description,
        'httpPort': httpPort,
        'longpollingPort': longpollingPort,
        'createdAt': createdAt,
        'favourite': favourite,
      };

  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
        name: (json['name'] ?? '').toString(),
        path: (json['path'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        httpPort: json['httpPort'] as int? ?? 8069,
        longpollingPort: json['longpollingPort'] as int? ?? 8072,
        createdAt: (json['createdAt'] ?? '').toString(),
        favourite: json['favourite'] as bool? ?? false,
      );
}
