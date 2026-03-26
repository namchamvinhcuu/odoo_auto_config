import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings, size: 28),
              const SizedBox(width: 12),
              Text('Settings',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Customize theme and appearance.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Theme mode
          Text('Theme Mode',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
              ),
            ],
            selected: {theme.themeMode},
            onSelectionChanged: (v) => theme.setThemeMode(v.first),
          ),
          const SizedBox(height: 32),

          // Accent color
          Text('Accent Color',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: theme.availableColors.entries.map((entry) {
              final isSelected =
                  entry.value.toARGB32() == theme.seedColor.toARGB32();
              return Tooltip(
                message: entry.key,
                child: InkWell(
                  onTap: () => theme.setSeedColor(entry.value),
                  borderRadius: BorderRadius.circular(24),
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
          const SizedBox(height: 32),

          // Preview
          Text('Preview',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                  onPressed: () {}, child: const Text('Filled Button')),
              const SizedBox(width: 8),
              FilledButton.tonal(
                  onPressed: () {}, child: const Text('Tonal Button')),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () {}, child: const Text('Outlined')),
            ],
          ),
        ],
      ),
    );
  }
}
