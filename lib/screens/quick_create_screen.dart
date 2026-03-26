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
import '../services/platform_service.dart';
import '../services/storage_service.dart';
import '../templates/odoo_templates.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';

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
  final _logs = <String>[];

  List<Profile> _profiles = [];
  Profile? _selectedProfile;
  String _baseDir = '';
  bool _loading = true;
  bool _creating = false;
  bool _done = false;
  String? _portError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final profilesJson = await StorageService.loadProfiles();
    final projectsJson = await StorageService.loadProjects();

    int maxHttp = 8068;
    int maxLp = 8071;
    for (final pr in projectsJson) {
      final hp = pr['httpPort'] as int? ?? 0;
      final lp = pr['longpollingPort'] as int? ?? 0;
      if (hp > maxHttp) maxHttp = hp;
      if (lp > maxLp) maxLp = lp;
    }

    setState(() {
      _profiles = profilesJson.map((j) => Profile.fromJson(j)).toList();
      if (_profiles.isNotEmpty) _selectedProfile = _profiles.first;
      _httpPortController.text = '${maxHttp + 1}';
      _longpollingPortController.text = '${maxLp + 1}';
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

      final readmePath = p.join(projectPath, 'README.md');
      await File(readmePath).writeAsString(
        OdooTemplates.readme(
          projectName: projectName,
          odooVersion: profile.odooVersion,
          httpPort: httpPort,
        ),
      );
      setState(() => _logs.add('[+] Written: $readmePath'));

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
        _done = true;
      });
    } catch (e) {
      setState(() => _logs.add('[ERROR] $e'));
    } finally {
      setState(() => _creating = false);
    }
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
                        IconButton(
                          onPressed: () => Navigator.pop(context, _done),
                          icon: const Icon(Icons.close),
                        ),
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
