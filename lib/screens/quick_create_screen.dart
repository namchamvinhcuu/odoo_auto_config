import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/folder_structure_config.dart';
import '../models/profile.dart';
import '../models/project_info.dart';
import '../services/folder_structure_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/storage_service.dart';
import '../templates/odoo_templates.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';
import '../widgets/nginx_setup_dialog.dart';

class QuickCreateDialog extends StatefulWidget {
  const QuickCreateDialog({super.key});

  @override
  State<QuickCreateDialog> createState() => _QuickCreateDialogState();
}

class _QuickCreateDialogState extends State<QuickCreateDialog> {
  final _folderService = FolderStructureService();
  final _projectNameController = TextEditingController();
  final _httpPortController = TextEditingController();
  final _longpollingPortController = TextEditingController();
  final _gitOrgController = TextEditingController();
  final _logs = <String>[];

  List<Profile> _profiles = [];
  Profile? _selectedProfile;
  String _baseDir = '';
  List<Map<String, dynamic>> _gitAccounts = [];
  Map<String, dynamic>? _selectedGitAccount;
  bool _loading = true;
  bool _creating = false;
  bool _done = false;
  String? _portError;
  ProjectInfo? _createdProject;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final profilesJson = await StorageService.loadProfiles();
    final projectsJson = await StorageService.loadProjects();
    final settings = await StorageService.loadSettings();
    final accounts = (settings['gitAccounts'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final defaultName = (settings['defaultGitAccount'] ?? '').toString();
    _gitAccounts = accounts;
    _selectedGitAccount = accounts.where((a) => a['name'] == defaultName).firstOrNull
        ?? (accounts.isNotEmpty ? accounts.first : null);

    // Find max port across all projects
    int maxPort = 8068;
    for (final pr in projectsJson) {
      final hp = pr['httpPort'] as int? ?? 0;
      final lp = pr['longpollingPort'] as int? ?? 0;
      if (hp > maxPort) maxPort = hp;
      if (lp > maxPort) maxPort = lp;
    }

    // Next pair: max+1 / max+2 (default 8069/8070)
    final nextHttp = maxPort + 1;
    final nextLp = maxPort + 2;

    setState(() {
      _profiles = profilesJson.map((j) => Profile.fromJson(j)).toList();
      if (_profiles.isNotEmpty) _selectedProfile = _profiles.first;
      _httpPortController.text = '$nextHttp';
      _longpollingPortController.text = '$nextLp';
      _loading = false;
    });
  }

  Future<void> _validatePorts() async {
    final httpPort = int.tryParse(_httpPortController.text) ?? 0;
    final lpPort = int.tryParse(_longpollingPortController.text) ?? 0;

    if (httpPort == lpPort) {
      setState(
          () => _portError = context.l10n.portsMustBeDifferent);
      return;
    }

    final conflict =
        await StorageService.checkPortConflict(httpPort, lpPort, null);
    setState(() => _portError = conflict);
  }

  Future<void> _create() async {
    final profile = _selectedProfile;
    final projectName = _projectNameController.text.trim();
    if (profile == null || _baseDir.isEmpty || projectName.isEmpty) return;

    final httpPort = int.tryParse(_httpPortController.text) ?? 8069;
    final lpPort = int.tryParse(_longpollingPortController.text) ?? 8072;

    final conflict =
        await StorageService.checkPortConflict(httpPort, lpPort, null);
    if (conflict != null) {
      setState(() {
        _portError = conflict;
        _logs.add('[ERROR] $conflict');
      });
      return;
    }

    setState(() {
      _creating = true;
      _portError = null;
      _logs.clear();
      _logs.add(
          '[+] Creating project "$projectName" with profile "${profile.name}"...');
    });

    try {
      final folderConfig = FolderStructureConfig(
        baseDirectory: _baseDir,
        projectName: projectName,
        odooSourcePath: profile.odooSourcePath,
        odooVersion: profile.odooVersion,
        createAddons: profile.createAddons,
        createThirdPartyAddons: profile.createThirdPartyAddons,
        createConfigDir: false,
        createVenvDir: false,
      );
      final folderLogs = await _folderService.generate(folderConfig);
      setState(() => _logs.addAll(folderLogs));

      final projectPath = folderConfig.projectPath;

      final confPath = p.join(projectPath, 'odoo.conf');
      final filestorePath = p.join(projectPath, 'filestore');
      await File(confPath).writeAsString(
        OdooTemplates.odooConf(
          httpPort: httpPort,
          longpollingPort: lpPort,
          projectPath: projectPath,
          filestorePath: filestorePath,
          dbHost: profile.dbHost,
          dbPort: profile.dbPort,
          dbUser: profile.dbUser,
          dbPassword: profile.dbPassword,
          dbSslmode: profile.dbSslmode,
        ),
      );
      setState(() => _logs.add('[+] Written: $confPath'));

      final vscodePath = p.join(projectPath, '.vscode');
      await Directory(vscodePath).create(recursive: true);
      setState(() => _logs.add('[+] Created: $vscodePath'));

      final launchConfig = {
        'name': 'Debug ${profile.name}',
        'type': 'debugpy',
        'request': 'launch',
        'python': PlatformService.venvPython(profile.venvPath),
        'program': profile.odooBinPath,
        'args': [
          '-c',
          '\${workspaceFolder}/odoo.conf',
          '--dev',
          'xml',
        ],
        'env': <String, dynamic>{},
        'console': 'integratedTerminal',
        'justMyCode': false,
      };

      final launch = {
        'version': '0.2.0',
        'configurations': [launchConfig],
      };

      final launchPath = p.join(vscodePath, 'launch.json');
      await File(launchPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(launch),
      );
      setState(() => _logs.add('[+] Written: $launchPath'));

      final settingsPath = p.join(vscodePath, 'settings.json');
      await File(settingsPath).writeAsString(OdooTemplates.vscodeSettings());
      setState(() => _logs.add('[+] Written: $settingsPath'));

      final readmePath = p.join(projectPath, 'README.md');
      await File(readmePath).writeAsString(
        OdooTemplates.readme(
          projectName: projectName,
          odooVersion: profile.odooVersion,
          httpPort: httpPort,
        ),
      );
      setState(() => _logs.add('[+] Written: $readmePath'));

      // Create git-repositories script (platform-specific)
      final gitOrg = _gitOrgController.text.trim();
      final gitToken = (_selectedGitAccount?['token'] ?? '').toString();
      if (Platform.isWindows) {
        final scriptPath = p.join(projectPath, 'git-repositories.ps1');
        await File(scriptPath).writeAsString(
            OdooTemplates.gitRepositoriesPs1(token: gitToken, org: gitOrg));
        setState(() => _logs.add('[+] Written: $scriptPath'));
      } else {
        final scriptPath = p.join(projectPath, 'git-repositories.sh');
        await File(scriptPath).writeAsString(
            OdooTemplates.gitRepositoriesSh(token: gitToken, org: gitOrg));
        await Process.run('chmod', ['+x', scriptPath], runInShell: true);
        setState(() => _logs.add('[+] Written: $scriptPath'));
      }

      // Create empty ignore_repos.txt
      final ignorePath = p.join(projectPath, 'ignore_repos.txt');
      await File(ignorePath).writeAsString('');
      setState(() => _logs.add('[+] Written: $ignorePath'));

      final projectInfo = ProjectInfo(
        name: projectName,
        path: projectPath,
        description: profile.name,
        httpPort: httpPort,
        longpollingPort: lpPort,
        createdAt: DateTime.now().toIso8601String(),
      );
      await StorageService.addProject(projectInfo.toJson());

      setState(() {
        _logs.add('');
        _logs.add('[+] Project created and saved!');
        _logs.add('[+] Path: $projectPath');
        _logs.add('[+] HTTP: $httpPort | Longpolling: $lpPort');
        _createdProject = projectInfo;
        _done = true;
      });
    } on SymlinkPermissionException catch (e) {
      if (mounted) {
        setState(() {
          _logs.add('[ERROR] $e');
          _creating = false;
        });
        _showSymlinkErrorDialog(e.message);
      }
      return;
    } catch (e) {
      setState(() => _logs.add('[ERROR] $e'));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _setupNginx() async {
    final proj = _createdProject;
    if (proj == null) return;

    final nginx = await NginxService.loadSettings();
    final suffix = (nginx['domainSuffix'] ?? '').toString();
    if (suffix.isEmpty || (nginx['confDir'] ?? '').toString().isEmpty) {
      if (mounted) {
        setState(() {
          _logs.add(
            '\x1B[0;31m[-] Nginx not configured. Go to Settings > Nginx first.\x1B[0m',
          );
        });
      }
      return;
    }

    final confDir = (nginx['confDir'] ?? '').toString();
    final existingSubs = await NginxService.getExistingSubdomains(confDir);
    final usedPorts = await NginxService.getUsedPorts();

    if (!mounted) return;
    final result = await showDialog<({String subdomain, int? port})>(
      context: context,
      builder: (ctx) => NginxSetupDialog(
        initialSubdomain: NginxService.sanitizeSubdomain(proj.name),
        domainSuffix: suffix,
        existingSubdomains: existingSubs,
        usedPorts: usedPorts,
      ),
    );
    if (result == null) return;

    try {
      final domain = await NginxService.setupOdoo(
        subdomain: result.subdomain,
        httpPort: proj.httpPort,
        longpollingPort: proj.longpollingPort,
      );
      final updated = proj.copyWith(nginxSubdomain: () => result.subdomain);
      await StorageService.removeProject(proj.path);
      await StorageService.addProject(updated.toJson());
      if (mounted) {
        setState(() {
          _createdProject = updated;
          _logs.add('\x1B[0;32m[+] Nginx setup: $domain\x1B[0m');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _logs.add('\x1B[0;31m[-] Nginx failed: $e\x1B[0m');
        });
      }
    }
  }

  void _showSymlinkErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: AppIconSize.lg),
            const SizedBox(width: AppSpacing.sm),
            Text(context.l10n.symlinkErrorTitle),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.symlinkErrorDesc),
              const SizedBox(height: AppSpacing.lg),
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.symlinkErrorSteps,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.sm),
                      Text(context.l10n.symlinkErrorStep1),
                      Text(context.l10n.symlinkErrorStep2),
                      Text(context.l10n.symlinkErrorStep3),
                      Text(context.l10n.symlinkErrorStep4),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(context.l10n.symlinkErrorRetry,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: AppFontSize.sm)),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canCreate =>
      !_creating &&
      _selectedProfile != null &&
      _baseDir.isNotEmpty &&
      _projectNameController.text.trim().isNotEmpty &&
      _portError == null;

  @override
  void dispose() {
    _projectNameController.dispose();
    _httpPortController.dispose();
    _longpollingPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDialog.widthLg, maxHeight: AppDialog.heightXl),
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.rocket_launch, size: AppIconSize.lg),
                        const SizedBox(width: AppSpacing.sm),
                        Text(context.l10n.quickCreateTitle,
                            style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        AppDialog.closeButton(context, onClose: () => Navigator.pop(context, _done)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    if (_profiles.isEmpty)
                      Padding(
                        padding: AppSpacing.cardPadding,
                        child: Text(
                            context.l10n.noProfilesFound),
                      )
                    else ...[
                      // Profile
                      DropdownButtonFormField<Profile>(
                        isExpanded: true,
                        initialValue: _selectedProfile,
                        decoration: InputDecoration(
                          labelText: context.l10n.profile,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _profiles
                            .map((pr) => DropdownMenuItem(
                                  value: pr,
                                  child: Text(
                                      '${pr.name}  (Odoo ${pr.odooVersion})'),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedProfile = v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Base directory
                      DirectoryPickerField(
                        label: context.l10n.baseDirectory,
                        value: _baseDir,
                        onChanged: (v) => setState(() => _baseDir = v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Project name
                      TextField(
                        controller: _projectNameController,
                        decoration: InputDecoration(
                          labelText: context.l10n.projectName,
                          hintText: context.l10n.projectNameHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Ports
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _httpPortController,
                              decoration: InputDecoration(
                                labelText: context.l10n.httpPort,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _validatePorts(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: TextField(
                              controller: _longpollingPortController,
                              decoration: InputDecoration(
                                labelText: context.l10n.longpollingPort,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _validatePorts(),
                            ),
                          ),
                        ],
                      ),

                      if (_portError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(_portError!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: AppFontSize.sm)),
                      ],
                      const SizedBox(height: AppSpacing.md),

                      // Git Account + Organization
                      if (_gitAccounts.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedGitAccount?['name'] as String?,
                          decoration: const InputDecoration(
                            labelText: 'Git Account',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: _gitAccounts.map<DropdownMenuItem<String>>((a) {
                            final name = (a['name'] ?? '').toString();
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedGitAccount = _gitAccounts
                                  .where((a) => a['name'] == v)
                                  .firstOrNull;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      TextField(
                        controller: _gitOrgController,
                        decoration: InputDecoration(
                          labelText: context.l10n.gitOrg,
                          hintText: context.l10n.gitOrgHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Create button
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _canCreate ? _create : null,
                            icon: _creating
                                ? const SizedBox(
                                    width: AppIconSize.md,
                                    height: AppIconSize.md,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.rocket_launch),
                            label: Text(_creating
                                ? context.l10n.creating
                                : context.l10n.createProject),
                          ),
                          if (_done) ...[
                            const SizedBox(width: AppSpacing.md),
                            const Icon(Icons.check_circle,
                                color: Colors.green),
                            const SizedBox(width: AppSpacing.xs),
                            Text(context.l10n.done,
                                style: const TextStyle(color: Colors.green)),
                            if (_createdProject != null &&
                                !_createdProject!.hasNginx) ...[
                              const SizedBox(width: AppSpacing.lg),
                              FilledButton.tonalIcon(
                                onPressed: _setupNginx,
                                icon: const Icon(Icons.dns),
                                label: Text(context.l10n.setupNginx),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),

                    // Log output
                    Flexible(child: LogOutput(lines: _logs, height: 180)),
                  ],
                ),
        ),
      ),
    );
  }
}
