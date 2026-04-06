import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';

class OdooProjectGridView extends StatelessWidget {
  const OdooProjectGridView({
    super.key,
    required this.projects,
    required this.onToggleFavourite,
    required this.onShowInfo,
    required this.onOpenWorkspace,
    required this.onGitPull,
    required this.onGitCommit,
    required this.onSelectivePull,
    required this.onOpenInVscode,
    required this.onOpenInFileManager,
    required this.onOpenInBrowser,
    required this.onRemove,
  });

  final List<ProjectInfo> projects;
  final ValueChanged<ProjectInfo> onToggleFavourite;
  final ValueChanged<ProjectInfo> onShowInfo;
  final ValueChanged<ProjectInfo> onOpenWorkspace;
  final ValueChanged<ProjectInfo> onGitPull;
  final ValueChanged<ProjectInfo> onGitCommit;
  final ValueChanged<ProjectInfo> onSelectivePull;
  final ValueChanged<ProjectInfo> onOpenInVscode;
  final ValueChanged<ProjectInfo> onOpenInFileManager;
  final ValueChanged<ProjectInfo> onOpenInBrowser;
  final ValueChanged<ProjectInfo> onRemove;

  int _gridCrossAxisCount(double width) {
    if (width >= 1100) return 4;
    if (width >= 800) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridCrossAxisCount(constraints.maxWidth);
        final cellWidth =
            (constraints.maxWidth - (columns - 1) * AppSpacing.sm) / columns;
        final nameSize = cellWidth >= 200 ? AppFontSize.xl : AppFontSize.lg;
        final portSize = cellWidth >= 200 ? AppFontSize.sm : AppFontSize.xs;
        final btnSize = cellWidth * 0.12;
        final btnBox = cellWidth * 0.18;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1,
          ),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final proj = projects[index];
            final exists = Directory(proj.path).existsSync();

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: proj.description.isNotEmpty ? proj.description : proj.path,
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  onTap: exists ? () => onOpenInVscode(proj) : null,
                  onSecondaryTapDown: (details) =>
                      _showGridContextMenu(context, details.globalPosition, proj, exists),
                  child: Column(
                    children: [
                      // Nginx banner
                      if (proj.hasNginx)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          color: Colors.teal,
                          child: Text(
                            'nginx',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: portSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Align(
                                alignment: Alignment.topRight,
                                child: IconButton(
                                  onPressed: () => onToggleFavourite(proj),
                                  icon: Icon(
                                    proj.favourite ? Icons.star : Icons.star_border,
                                    size: AppIconSize.lg,
                                    color: proj.favourite ? Colors.amber : Colors.grey.shade600,
                                  ),
                                  tooltip: proj.favourite ? context.l10n.unfavourite : context.l10n.favourite,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                              ),
                              const Spacer(),
                              // Odoo badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.xs),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withValues(alpha: 0.15),
                                  borderRadius: AppRadius.mediumBorderRadius,
                                ),
                                child: Text(
                                  'Odoo',
                                  style: TextStyle(
                                    fontSize: portSize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              // Project name
                              Text(
                                proj.name,
                                style: TextStyle(
                                  fontSize: nameSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              // Ports info
                              Text(
                                '${proj.httpPort} / ${proj.longpollingPort}',
                                style: TextStyle(
                                  fontSize: portSize,
                                  color: Colors.grey,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const Spacer(),
                              // Quick actions
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: AppSpacing.lg,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  _gridBtn(
                                    icon: Icons.info_outline,
                                    tooltip: context.l10n.projectInfo,
                                    onPressed: () => onShowInfo(proj),
                                    iconSize: btnSize,
                                    boxSize: btnBox,
                                  ),
                                  if (proj.hasNginx)
                                    _gridBtn(
                                      icon: Icons.language,
                                      tooltip: context.l10n.openInBrowser,
                                      onPressed: () => onOpenInBrowser(proj),
                                      iconSize: btnSize,
                                      boxSize: btnBox,
                                    ),
                                  if (exists) ...[
                                    _gridBtn(
                                      icon: Icons.workspaces,
                                      tooltip: context.l10n.workspaceView,
                                      onPressed: () => onOpenWorkspace(proj),
                                      iconSize: btnSize,
                                      boxSize: btnBox,
                                    ),
                                    // Selective Pull — hidden, use Workspace View instead
                                    // _gridBtn(
                                    //   icon: Icons.checklist,
                                    //   tooltip: context.l10n.gitSelectivePull,
                                    //   onPressed: () => onSelectivePull(proj),
                                    //   iconSize: btnSize,
                                    //   boxSize: btnBox,
                                    // ),
                                    _gridBtn(
                                      icon: Icons.commit,
                                      tooltip: context.l10n.gitCommit,
                                      onPressed: () => onGitCommit(proj),
                                      iconSize: btnSize,
                                      boxSize: btnBox,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showGridContextMenu(
      BuildContext context, Offset position, ProjectInfo proj, bool exists) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: AppIconSize.md),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.projectInfo),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favourite',
          child: Row(
            children: [
              Icon(proj.favourite ? Icons.star : Icons.star_border,
                  size: AppIconSize.md,
                  color: proj.favourite ? Colors.amber : null),
              const SizedBox(width: AppSpacing.sm),
              Text(proj.favourite ? context.l10n.unfavourite : context.l10n.favourite),
            ],
          ),
        ),
        if (exists)
          PopupMenuItem(
            value: 'workspace_view',
            child: Row(
              children: [
                const Icon(Icons.workspaces, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.workspaceView),
              ],
            ),
          ),
        // Selective Pull — hidden, use Workspace View instead
        // if (exists)
        //   PopupMenuItem(
        //     value: 'git_selective_pull',
        //     child: Row(
        //       children: [
        //         const Icon(Icons.checklist, size: AppIconSize.md),
        //         const SizedBox(width: AppSpacing.sm),
        //         Text(context.l10n.gitSelectivePull),
        //       ],
        //     ),
        //   ),
        if (exists)
          PopupMenuItem(
            value: 'git_pull',
            child: Row(
              children: [
                const Icon(Icons.sync, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.gitPull),
              ],
            ),
          ),
        if (exists)
          PopupMenuItem(
            value: 'git_commit',
            child: Row(
              children: [
                const Icon(Icons.commit, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.gitCommit),
              ],
            ),
          ),
        if (exists)
          PopupMenuItem(
            value: 'folder',
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.openFolder),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, size: AppIconSize.md, color: Colors.red),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.removeFromList,
                  style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
    if (result == null || !context.mounted) return;
    switch (result) {
      case 'info':
        onShowInfo(proj);
      case 'favourite':
        onToggleFavourite(proj);
      case 'workspace_view':
        onOpenWorkspace(proj);
      case 'git_pull':
        onGitPull(proj);
      case 'git_selective_pull':
        onSelectivePull(proj);
      case 'git_commit':
        onGitCommit(proj);
      case 'folder':
        onOpenInFileManager(proj);
      case 'delete':
        onRemove(proj);
    }
  }

  Widget _gridBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required double iconSize,
    required double boxSize,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: boxSize, minHeight: boxSize),
    );
  }
}
