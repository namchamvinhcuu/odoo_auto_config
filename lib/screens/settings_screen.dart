import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../services/locale_service.dart';
import '../services/nginx_service.dart';
import '../services/platform_service.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _confDirController = TextEditingController();
  final _domainSuffixController = TextEditingController();
  final _containerNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNginxSettings();
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
          ],
        ),
      ),
    );
  }
}
