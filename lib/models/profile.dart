class Profile {
  final String id;
  final String name;
  final String venvPath;
  final String odooBinPath;
  final String odooSourcePath;
  final int odooVersion;
  final bool createAddons;
  final bool createThirdPartyAddons;
  final bool createConfigDir;

  const Profile({
    required this.id,
    required this.name,
    required this.venvPath,
    required this.odooBinPath,
    this.odooSourcePath = '',
    this.odooVersion = 17,
    this.createAddons = true,
    this.createThirdPartyAddons = true,
    this.createConfigDir = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'venvPath': venvPath,
        'odooBinPath': odooBinPath,
        'odooSourcePath': odooSourcePath,
        'odooVersion': odooVersion,
        'createAddons': createAddons,
        'createThirdPartyAddons': createThirdPartyAddons,
        'createConfigDir': createConfigDir,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        venvPath: json['venvPath'] as String? ?? '',
        odooBinPath: json['odooBinPath'] as String? ?? '',
        odooSourcePath: (json['odooSourcePath'] ?? '').toString(),
        odooVersion: json['odooVersion'] as int? ?? 17,
        createAddons: json['createAddons'] as bool? ?? true,
        createThirdPartyAddons:
            json['createThirdPartyAddons'] as bool? ?? true,
        createConfigDir: json['createConfigDir'] as bool? ?? true,
      );
}
