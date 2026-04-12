import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/locale_provider.dart';
import 'package:odoo_auto_config/providers/theme_provider.dart';
// TODO: re-enable tray when ready
// import 'package:odoo_auto_config/services/tray_service.dart';

class ThemeTab extends ConsumerWidget {
  const ThemeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final locale = ref.watch(localeProvider);
    final localeNotifier = ref.read(localeProvider.notifier);

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language
          Text(context.l10n.language,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<Locale?>(
            segments: LocaleNotifier.supportedLocales.map((loc) {
              return ButtonSegment(
                value: loc,
                label: Text(
                    LocaleNotifier.localeNames[loc.languageCode] ?? ''),
              );
            }).toList(),
            selected: {
              locale ??
                  LocaleNotifier.supportedLocales.firstWhere(
                    (l) =>
                        l.languageCode ==
                        Localizations.localeOf(context).languageCode,
                    orElse: () => const Locale('en'),
                  ),
            },
            onSelectionChanged: (v) => localeNotifier.setLocale(v.first),
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
                  label: Text(context.l10n.themeSystem)),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode),
                  label: Text(context.l10n.themeLight)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode),
                  label: Text(context.l10n.themeDark)),
            ],
            selected: {theme.themeMode},
            onSelectionChanged: (v) => themeNotifier.setThemeMode(v.first),
          ),
          const SizedBox(height: AppSpacing.xxxl),

          // Accent color
          Text(context.l10n.accentColor,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: ThemeNotifier.availableColors.entries.map((entry) {
              final isSelected =
                  entry.value.toARGB32() == theme.seedColor.toARGB32();
              return Tooltip(
                message: entry.key,
                child: InkWell(
                  onTap: () => themeNotifier.setSeedColor(entry.value),
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

          // TODO: re-enable tray when ready
          // if (TrayService.supported) ...[
          //   Text(context.l10n.closeBehavior,
          //       style: Theme.of(context).textTheme.titleMedium),
          //   const SizedBox(height: AppSpacing.md),
          //   Row(
          //     children: [
          //       const Icon(Icons.hide_source, size: AppIconSize.md),
          //       const SizedBox(width: AppSpacing.sm),
          //       Text(context.l10n.closeBehaviorTray),
          //     ],
          //   ),
          //   const SizedBox(height: AppSpacing.xxxl),
          // ],

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
        ],
      ),
    );
  }
}
