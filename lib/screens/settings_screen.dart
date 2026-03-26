import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../services/locale_service.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    final localeService = context.watch<LocaleService>();

    return Padding(
      padding: AppSpacing.screenPadding,
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
          Row(
            children: [
              FilledButton(
                  onPressed: () {}, child: Text(context.l10n.filledButton)),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.tonal(
                  onPressed: () {}, child: Text(context.l10n.tonalButton)),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                  onPressed: () {}, child: Text(context.l10n.outlined)),
            ],
          ),
        ],
      ),
    );
  }
}
