import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/folder_structure_config.dart';
import '../models/profile.dart';
import '../models/project_info.dart';
import '../services/folder_structure_service.dart';
import '../services/storage_service.dart';
import '../templates/odoo_templates.dart';
import '../widgets/directory_picker_field.dart';
import '../widgets/log_output.dart';

class QuickCreateScreen extends StatefulWidget {
  const QuickCreateScreen({super.key});

  @override
  State<QuickCreateScreen> createState() => _QuickCreateScreenState();
}

class _QuickCreateScreenState extends State<QuickCreateScreen> {
  final _folderService = FolderStructureService();
  final _projectNameController = TextEditingController();
  final _httpPortController = TextEditingController(text: '8069');
  final _longpollingPortController = TextEditingController(text: '8072');
  final _logs = <String>[];

  List<Profile> _profiles = [];
  Profile? _selectedProfile;
  String _baseDir = '';
  bool _loading = true;
  bool _creating = false;
  String? _portError;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() => _loading = true);
    final json = await StorageService.loadProfiles();
    setState(() {
      _profiles = json.map((j) => Profile.fromJson(j)).toList();
      if (_profiles.isNotEmpty) {
        _selectedProfile = _profiles.first;
      }
      _loading = false;
    });
  }

  Future<void> _validatePorts() async {
    final httpPort = int.tryParse(_httpPortController.text) ?? 0;
    final lpPort = int.tryParse(_longpollingPortController.text) ?? 0;

    if (httpPort == lpPort) {
      setState(() => _portError = 'HTTP and longpolling ports must be different');
      return;
    }

    final conflict = await StorageService.checkPortConflict(
        httpPort, lpPort, null);
    setState(() => _portError = conflict);
  }

  Future<void> _create() async {
    final profile = _selectedProfile;
    final projectName = _projectNameController.text.trim();
    if (profile == null || _baseDir.isEmpty || projectName.isEmpty) {
      return;
    }

    final httpPort = int.tryParse(_httpPortController.text) ?? 8069;
    final lpPort = int.tryParse(_longpollingPortController.text) ?? 8072;

    // Validate ports before creating
    final conflict = await StorageService.checkPortConflict(
        httpPort, lpPort, null);
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
      // 1. Create folder structure
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

      // 2. Create odoo.conf at project root
      final confPath = p.join(projectPath, 'odoo.conf');
      final filestorePath = p.join(projectPath, 'filestore');
      await File(confPath).writeAsString(
        OdooTemplates.odooConf(
          httpPort: httpPort,
          longpollingPort: lpPort,
          projectPath: projectPath,
          filestorePath: filestorePath,
        ),
      );
      setState(() => _logs.add('[+] Written: $confPath'));

      // 3. Create .vscode/launch.json
      final vscodePath = p.join(projectPath, '.vscode');
      await Directory(vscodePath).create(recursive: true);
      setState(() => _logs.add('[+] Created: $vscodePath'));

      final launchConfig = {
        'name': 'Debug ${profile.name}',
        'type': 'debugpy',
        'request': 'launch',
        'python': '${profile.venvPath}/bin/python',
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

      // 4. Create README
      final readmePath = p.join(projectPath, 'README.md');
      await File(readmePath).writeAsString(
        OdooTemplates.readme(
          projectName: projectName,
          odooVersion: profile.odooVersion,
          httpPort: httpPort,
        ),
      );
      setState(() => _logs.add('[+] Written: $readmePath'));

      // 5. Save project to storage
      final projectInfo = ProjectInfo(
        name: projectName,
        path: projectPath,
        profileName: profile.name,
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
        _logs.add('');
        _logs.add('[+] Open $projectPath in VSCode');
        _logs.add(
            '[+] Select "Debug ${profile.name}" in debug panel');
      });
    } catch (e) {
      setState(() => _logs.add('[ERROR] $e'));
    } finally {
      setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _httpPortController.dispose();
    _longpollingPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rocket_launch, size: 28),
              const SizedBox(width: 12),
              Text('Quick Create',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select a profile, choose directory, name your project, done.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          if (_profiles.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: Colors.orange),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                          'No profiles found. Go to Profiles tab to create one first.'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Profile selector
            DropdownButtonFormField<Profile>(
              isExpanded: true,
              initialValue: _selectedProfile,
              decoration: const InputDecoration(
                labelText: 'Profile',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.person),
              ),
              items: _profiles
                  .map((pr) => DropdownMenuItem(
                        value: pr,
                        child: Text(
                            '${pr.name}  (Odoo ${pr.odooVersion})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedProfile = v),
            ),
            const SizedBox(height: 16),

            // Base directory
            DirectoryPickerField(
              label: 'Base Directory',
              value: _baseDir,
              onChanged: (v) => setState(() => _baseDir = v),
            ),
            const SizedBox(height: 16),

            // Project name
            TextField(
              controller: _projectNameController,
              decoration: const InputDecoration(
                labelText: 'Project Name',
                hintText: 'e.g. my_odoo_project',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.folder),
              ),
            ),
            const SizedBox(height: 16),

            // Ports
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _httpPortController,
                    decoration: const InputDecoration(
                      labelText: 'HTTP Port',
                      hintText: '8069',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.lan),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _validatePorts(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _longpollingPortController,
                    decoration: const InputDecoration(
                      labelText: 'Longpolling Port',
                      hintText: '8072',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.sync),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _validatePorts(),
                  ),
                ),
              ],
            ),

            // Port error
            if (_portError != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_portError!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Create button
            FilledButton.icon(
              onPressed: (_creating ||
                      _selectedProfile == null ||
                      _baseDir.isEmpty ||
                      _projectNameController.text.trim().isEmpty ||
                      _portError != null)
                  ? null
                  : _create,
              icon: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rocket_launch),
              label:
                  Text(_creating ? 'Creating...' : 'Create Project'),
            ),
          ],
          const SizedBox(height: 16),

          Expanded(child: LogOutput(lines: _logs)),
        ],
      ),
    );
  }
}
