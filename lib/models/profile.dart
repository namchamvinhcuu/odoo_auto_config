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
  // DB connection
  final String dbHost;
  final int dbPort;
  final String dbUser;
  final String dbPassword;
  final String dbSslmode;

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
    this.dbHost = 'localhost',
    this.dbPort = 5432,
    this.dbUser = 'odoo',
    this.dbPassword = '',
    this.dbSslmode = 'prefer',
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
        'dbHost': dbHost,
        'dbPort': dbPort,
        'dbUser': dbUser,
        'dbPassword': dbPassword,
        'dbSslmode': dbSslmode,
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
        dbHost: (json['dbHost'] ?? 'localhost').toString(),
        dbPort: json['dbPort'] as int? ?? 5432,
        dbUser: (json['dbUser'] ?? 'odoo').toString(),
        dbPassword: (json['dbPassword'] ?? '').toString(),
        dbSslmode: (json['dbSslmode'] ?? 'prefer').toString(),
      );
}
