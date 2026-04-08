import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';

class OdooProjectListView extends StatelessWidget {
  const OdooProjectListView({
    super.key,
    required this.projects,
    required this.onToggleFavourite,
    required this.onShowInfo,
    required this.onOpenWorkspace,
    required this.onGitPull,
    required this.onGitCommit,
    required this.onOpenInVscode,
    required this.onRemove,
  });

  final List<ProjectInfo> projects;
  final ValueChanged<ProjectInfo> onToggleFavourite;
  final ValueChanged<ProjectInfo> onShowInfo;
  final ValueChanged<ProjectInfo> onOpenWorkspace;
  final ValueChanged<ProjectInfo> onGitPull;
  final ValueChanged<ProjectInfo> onGitCommit;
  final ValueChanged<ProjectInfo> onOpenInVscode;
  final ValueChanged<ProjectInfo> onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final proj = projects[index];
        final exists = Directory(proj.path).existsSync();

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      exists ? Icons.folder_special : Icons.folder_off,
                      color: exists ? Colors.deepPurple : Colors.grey,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        proj.name,
                        style: const TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Chip(
                      avatar: const Icon(Icons.lan, size: AppIconSize.sm),
                      label: Text(
                          context.l10n.projectHttpPort(proj.httpPort)),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Chip(
                      avatar: const Icon(Icons.sync, size: AppIconSize.sm),
                      label: Text(
                          context.l10n.projectLpPort(proj.longpollingPort)),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (proj.hasDb) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Chip(
                        label: Text(proj.dbName!),
                        avatar: const Icon(Icons.storage,
                            size: AppIconSize.md),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                    if (proj.description.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Chip(
                          label: Text(proj.description,
                              overflow: TextOverflow.ellipsis),
                          avatar: const Icon(Icons.description,
                              size: AppIconSize.md),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  proj.path,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppFontSize.sm,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => onToggleFavourite(proj),
                      icon: Icon(
                        proj.favourite ? Icons.star : Icons.star_border,
                        color: proj.favourite ? Colors.amber : null,
                      ),
                      tooltip: proj.favourite ? context.l10n.unfavourite : context.l10n.favourite,
                    ),
                    IconButton(
                      onPressed: () => onShowInfo(proj),
                      icon: const Icon(Icons.info_outline),
                      tooltip: context.l10n.projectInfo,
                    ),
                    if (exists) ...[
                      IconButton(
                        onPressed: () => onOpenWorkspace(proj),
                        icon: const Icon(Icons.workspaces),
                        tooltip: context.l10n.workspaceView,
                      ),
                      IconButton(
                        onPressed: () => onGitPull(proj),
                        icon: const Icon(Icons.download),
                        tooltip: context.l10n.gitPull,
                      ),
                      // Selective Pull — hidden, use Workspace View instead
                      // IconButton(
                      //   onPressed: () => onSelectivePull(proj),
                      //   icon: const Icon(Icons.checklist),
                      //   tooltip: context.l10n.gitSelectivePull,
                      // ),
                      IconButton(
                        onPressed: () => onGitCommit(proj),
                        icon: const Icon(Icons.commit),
                        tooltip: context.l10n.gitCommit,
                      ),
                      IconButton(
                        onPressed: () => onOpenInVscode(proj),
                        icon: const Icon(Icons.code),
                        tooltip: context.l10n.openInVscode,
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      onPressed: () => onRemove(proj),
                      icon: const Icon(Icons.delete),
                      color: Colors.red,
                      tooltip: context.l10n.removeFromList,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
