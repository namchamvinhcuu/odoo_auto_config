import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../models/python_info.dart';
import '../services/docker_install_service.dart';
import '../services/locale_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/python_checker_service.dart';
import '../services/python_install_service.dart';
import '../services/theme_service.dart';
import '../widgets/log_output.dart';
import '../widgets/status_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _confDirController = TextEditingController();
  final _domainSuffixController = TextEditingController();
  final _containerNameController = TextEditingController();

  // Python + Docker state
  final _pythonChecker = PythonCheckerService();
  List<PythonInfo>? _pythonResults;
  bool _pythonLoading = false;
  bool? _dockerInstalled;
  bool? _dockerRunning;
  String? _dockerVersion;
  String? _dockerComposeVersion;

  @override
  void initState() {
    super.initState();
    _loadNginxSettings();
    _scanEnvironment();
  }

  Future<void> _scanEnvironment() async {
    setState(() => _pythonLoading = true);
    try {
      final results = await _pythonChecker.detectAll();
      final dInstalled = await DockerInstallService.isInstalled();
      final dRunning = dInstalled ? await DockerInstallService.isRunning() : false;
      final dVersion = dInstalled ? await DockerInstallService.getVersion() : null;
      final dCompose = dInstalled ? await DockerInstallService.getComposeVersion() : null;
      if (mounted) {
        setState(() {
          _pythonResults = results;
          _dockerInstalled = dInstalled;
          _dockerRunning = dRunning;
          _dockerVersion = dVersion;
          _dockerComposeVersion = dCompose;
          _pythonLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _pythonLoading = false);
    }
  }

  String _majorMinor(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) return '${parts[0]}.${parts[1]}';
    return version;
  }

  void _showPythonInstallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PythonInstallDialog(
        installedVersions:
            _pythonResults?.map((r) => _majorMinor(r.version)).toSet() ?? {},
        onInstalled: () => _scanEnvironment(),
      ),
    );
  }

  void _showDockerInstallDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _DockerInstallDialog(
        onInstalled: () => _scanEnvironment(),
      ),
    );
  }

  Future<void> _loadNginxSettings() async {
    final nginx = await NginxService.loadSettings();
    _confDirController.text = (nginx['confDir'] ?? '').toString();
    _domainSuffixController.text = (nginx['domainSuffix'] ?? '').toString();
    _containerNameController.text =
        (nginx['containerName'] ?? 'nginx').toString();
  }

  Future<void> _saveNginxSettings() async {
    await NginxService.saveSettings({
      'confDir': _confDirController.text.trim(),
      'domainSuffix': _domainSuffixController.text.trim(),
      'containerName': _containerNameController.text.trim(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nginxSaved)),
      );
    }
  }

  Future<void> _pickConfDir() async {
    String? path;
    if (PlatformService.isWindows) {
      path = await PlatformService.pickDirectory(
        dialogTitle: context.l10n.nginxConfDir,
      );
    } else {
      path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: context.l10n.nginxConfDir,
      );
    }
    if (path != null) {
      _confDirController.text = path;
    }
  }

  @override
  void dispose() {
    _confDirController.dispose();
    _domainSuffixController.dispose();
    _containerNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    final localeService = context.watch<LocaleService>();

    return Padding(
      padding: AppSpacing.screenPadding,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, size: AppIconSize.xl),
                const SizedBox(width: AppSpacing.md),
                Text(context.l10n.settingsTitle,
                    style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.settingsSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // Language
            Text(context.l10n.language,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<Locale?>(
              segments: LocaleService.supportedLocales.map((locale) {
                return ButtonSegment(
                  value: locale,
                  label: Text(
                      LocaleService.localeNames[locale.languageCode] ?? ''),
                );
              }).toList(),
              selected: {
                localeService.locale ??
                    LocaleService.supportedLocales.firstWhere(
                      (l) =>
                          l.languageCode ==
                          Localizations.localeOf(context).languageCode,
                      orElse: () => const Locale('en'),
                    ),
              },
              onSelectionChanged: (v) => localeService.setLocale(v.first),
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Theme mode
            Text(context.l10n.themeMode,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto),
                  label: Text(context.l10n.themeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode),
                  label: Text(context.l10n.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode),
                  label: Text(context.l10n.themeDark),
                ),
              ],
              selected: {theme.themeMode},
              onSelectionChanged: (v) => theme.setThemeMode(v.first),
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Accent color
            Text(context.l10n.accentColor,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: theme.availableColors.entries.map((entry) {
                final isSelected =
                    entry.value.toARGB32() == theme.seedColor.toARGB32();
                return Tooltip(
                  message: entry.key,
                  child: InkWell(
                    onTap: () => theme.setSeedColor(entry.value),
                    borderRadius: AppRadius.circularBorderRadius,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color:
                                    Theme.of(context).colorScheme.onSurface,
                                width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Preview
            Text(context.l10n.preview,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton(
                    onPressed: () {}, child: Text(context.l10n.filledButton)),
                FilledButton.tonal(
                    onPressed: () {}, child: Text(context.l10n.tonalButton)),
                OutlinedButton(
                    onPressed: () {}, child: Text(context.l10n.outlined)),
              ],
            ),
            const SizedBox(height: AppSpacing.xxxl),
            const Divider(),
            const SizedBox(height: AppSpacing.xxl),

            // ── Nginx Reverse Proxy ──
            Text(context.l10n.nginxSettings,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _confDirController,
                    decoration: InputDecoration(
                      labelText: context.l10n.nginxConfDir,
                      hintText: context.l10n.nginxConfDirHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  onPressed: _pickConfDir,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _domainSuffixController,
                    decoration: InputDecoration(
                      labelText: context.l10n.nginxDomainSuffix,
                      hintText: context.l10n.nginxDomainSuffixHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: TextField(
                    controller: _containerNameController,
                    decoration: InputDecoration(
                      labelText: context.l10n.nginxContainerName,
                      hintText: context.l10n.nginxContainerNameHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _saveNginxSettings,
              icon: const Icon(Icons.save),
              label: Text(context.l10n.save),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            const Divider(),
            const SizedBox(height: AppSpacing.xxl),

            // ── Environment Check ──
            Row(
              children: [
                Text(context.l10n.pythonCheckTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _pythonLoading ? null : _showPythonInstallDialog,
                  icon: const Icon(Icons.download),
                  label: Text(context.l10n.installPython),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  onPressed: _pythonLoading ? null : _scanEnvironment,
                  icon: const Icon(Icons.refresh),
                  tooltip: context.l10n.rescan,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Docker card
            if (_dockerInstalled != null)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    children: [
                      Icon(Icons.sailing,
                          color: _dockerInstalled == true
                              ? Colors.blue
                              : Colors.grey,
                          size: AppIconSize.xl),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.dockerStatus,
                                style: const TextStyle(
                                    fontSize: AppFontSize.lg,
                                    fontWeight: FontWeight.bold)),
                            if (_dockerVersion != null)
                              Text(_dockerVersion!,
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: AppFontSize.sm,
                                      color: Colors.grey.shade600)),
                            if (_dockerComposeVersion != null)
                              Text(_dockerComposeVersion!,
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: AppFontSize.sm,
                                      color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      if (_dockerInstalled == true) ...[
                        _envChip(context.l10n.dockerInstalled, true),
                        const SizedBox(width: AppSpacing.sm),
                        _envChip(
                          _dockerRunning == true
                              ? context.l10n.dockerRunning
                              : context.l10n.dockerStopped,
                          _dockerRunning == true,
                        ),
                      ] else ...[
                        _envChip(context.l10n.dockerNotInstalled, false),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: _showDockerInstallDialog,
                          icon: const Icon(Icons.download),
                          label: Text(context.l10n.dockerInstall),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Python list
            if (_pythonLoading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_pythonResults != null && _pythonResults!.isEmpty)
              StatusCard(
                title: context.l10n.noPythonFound,
                subtitle: context.l10n.noPythonFoundSubtitle,
                status: StatusType.warning,
              )
            else if (_pythonResults != null)
              ...List.generate(_pythonResults!.length, (i) {
                final info = _pythonResults![i];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: Row(
                      children: [
                        const Icon(Icons.code, color: Colors.blue),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.pythonVersion(info.version),
                                style: const TextStyle(
                                    fontSize: AppFontSize.lg,
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                info.executablePath,
                                style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.sm,
                                    color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        _envChip(
                            context.l10n.pipVersion(info.pipVersion),
                            info.hasPip),
                        const SizedBox(width: AppSpacing.sm),
                        _envChip(context.l10n.venvModule, info.hasVenv),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }

  Widget _envChip(String label, bool ok) {
    return Chip(
      avatar: Icon(
        ok ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: ok ? Colors.green : Colors.red,
      ),
      label: Text(label),
      backgroundColor:
          ok ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
    );
  }
}

// ── Python Install Dialog ──

class _PythonInstallDialog extends StatefulWidget {
  final Set<String> installedVersions;
  final VoidCallback onInstalled;

  const _PythonInstallDialog({
    required this.installedVersions,
    required this.onInstalled,
  });

  @override
  State<_PythonInstallDialog> createState() => _PythonInstallDialogState();
}

class _PythonInstallDialogState extends State<_PythonInstallDialog> {
  String? _selectedVersion;
  bool _installing = false;
  bool? _pmAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkPM();
  }

  Future<void> _checkPM() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = ok);
  }

  Future<void> _install() async {
    if (_selectedVersion == null) return;
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    final exitCode = await PythonInstallService.install(
      _selectedVersion!,
      (line) {
        if (mounted) setState(() => _logLines.add(line));
      },
    );
    if (mounted) {
      setState(() => _installing = false);
      if (exitCode == 0) widget.onInstalled();
    }
  }

  String _pmNotFound(BuildContext context) {
    if (PlatformService.isWindows) return context.l10n.packageManagerNotFoundWindows;
    if (PlatformService.isMacOS) return context.l10n.packageManagerNotFoundMac;
    return context.l10n.packageManagerNotFoundLinux;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.installPythonTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.installPythonSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: AppSpacing.lg),
            if (_pmAvailable == null)
              const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
            else if (_pmAvailable == false)
              StatusCard(title: context.l10n.packageManagerNotFound, subtitle: _pmNotFound(context), status: StatusType.error)
            else ...[
              Text(context.l10n.selectVersion, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: PythonInstallService.availableVersions.map((v) {
                  final installed = widget.installedVersions.contains(v.version);
                  return ChoiceChip(
                    label: Text(installed ? '${v.label} ✓' : v.label),
                    selected: _selectedVersion == v.version,
                    onSelected: (_installing || installed) ? null : (s) => setState(() => _selectedVersion = s ? v.version : null),
                  );
                }).toList(),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _installing ? null : () => Navigator.pop(context), child: Text(context.l10n.close)),
        if (_pmAvailable == true)
          FilledButton.icon(
            onPressed: (_installing || _selectedVersion == null) ? null : _install,
            icon: _installing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_installing ? context.l10n.installing : context.l10n.install),
          ),
      ],
    );
  }
}

// ── Docker Install Dialog ──

class _DockerInstallDialog extends StatefulWidget {
  final VoidCallback onInstalled;
  const _DockerInstallDialog({required this.onInstalled});

  @override
  State<_DockerInstallDialog> createState() => _DockerInstallDialogState();
}

class _DockerInstallDialogState extends State<_DockerInstallDialog> {
  bool _installing = false;
  bool? _pmAvailable;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    _checkPM();
  }

  Future<void> _checkPM() async {
    final ok = await PythonInstallService.isPackageManagerAvailable();
    if (mounted) setState(() => _pmAvailable = ok);
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _logLines.clear();
    });
    final exitCode = await DockerInstallService.install((line) {
      if (mounted) setState(() => _logLines.add(line));
    });
    if (mounted) {
      setState(() => _installing = false);
      if (exitCode == 0) widget.onInstalled();
    }
  }

  String _pmNotFound(BuildContext context) {
    if (PlatformService.isWindows) return context.l10n.packageManagerNotFoundWindows;
    if (PlatformService.isMacOS) return context.l10n.packageManagerNotFoundMac;
    return context.l10n.packageManagerNotFoundLinux;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.dockerInstallTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.dockerInstallSubtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: AppSpacing.lg),
            if (_pmAvailable == null)
              const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
            else if (_pmAvailable == false)
              StatusCard(title: context.l10n.packageManagerNotFound, subtitle: _pmNotFound(context), status: StatusType.error)
            else ...[
              Text(DockerInstallService.installCommand().description,
                  style: TextStyle(fontFamily: 'monospace', fontSize: AppFontSize.sm, color: Colors.grey.shade600)),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                LogOutput(lines: _logLines, height: 200),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _installing ? null : () => Navigator.pop(context), child: Text(context.l10n.close)),
        if (_pmAvailable == true)
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: _installing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_installing ? context.l10n.installing : context.l10n.dockerInstall),
          ),
      ],
    );
  }
}
