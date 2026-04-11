import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';

class OtherProjectGridView extends StatelessWidget {
  const OtherProjectGridView({
    super.key,
    required this.workspaces,
    required this.state,
    required this.onToggleFavourite,
    required this.onGitPull,
    required this.onGitCommit,
    required this.onOpenInVscode,
    required this.onOpenInFileManager,
    required this.onEdit,
    required this.onSetupNginx,
    required this.onRemoveNginx,
    required this.onRemove,
    required this.onSwitchBranch,
    required this.branchColor,
    required this.colorForType,
  });

  final List<WorkspaceInfo> workspaces;
  final OtherProjectsState state;
  final ValueChanged<WorkspaceInfo> onToggleFavourite;
  final ValueChanged<WorkspaceInfo> onGitPull;
  final ValueChanged<WorkspaceInfo> onGitCommit;
  final ValueChanged<WorkspaceInfo> onOpenInVscode;
  final ValueChanged<WorkspaceInfo> onOpenInFileManager;
  final ValueChanged<WorkspaceInfo> onEdit;
  final ValueChanged<WorkspaceInfo> onSetupNginx;
  final ValueChanged<WorkspaceInfo> onRemoveNginx;
  final ValueChanged<WorkspaceInfo> onRemove;
  final ValueChanged<WorkspaceInfo> onSwitchBranch;
  final Color Function(String) branchColor;
  final Color Function(String) colorForType;

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
        final btnSize = cellWidth * 0.12;
        final btnBox = cellWidth * 0.18;

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1,
          ),
          itemCount: workspaces.length,
          itemBuilder: (context, index) {
            final ws = workspaces[index];
            final exists = Directory(ws.path).existsSync();
            final color = exists ? colorForType(ws.type) : Colors.grey;

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: ws.description.isNotEmpty ? ws.description : ws.path,
                waitDuration: const Duration(milliseconds: 500),
                child: InkWell(
                  onTap: exists ? () => onOpenInVscode(ws) : null,
                  onSecondaryTapDown: (details) =>
                      _showGridContextMenu(context, details.globalPosition, ws, exists),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Top row: type (left) + star (right)
                        Stack(
                          children: [
                            if (ws.type.isNotEmpty)
                              Align(
                                alignment: Alignment.topLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: AppRadius.smallBorderRadius,
                                  ),
                                  child: Text(
                                    ws.type,
                                    style: TextStyle(
                                      fontSize: AppFontSize.xs,
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                onPressed: () => onToggleFavourite(ws),
                                icon: Icon(
                                  ws.favourite ? Icons.star : Icons.star_border,
                                  size: AppIconSize.lg,
                                  color: ws.favourite
                                      ? Colors.amber
                                      : Colors.grey.shade600,
                                ),
                                tooltip: ws.favourite
                                    ? context.l10n.unfavourite
                                    : context.l10n.favourite,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Branch badge
                        if (state.branches.containsKey(ws.path)) ...[
                          InkWell(
                            onTap: () => onSwitchBranch(ws),
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: AppRadius.smallBorderRadius,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: branchColor(
                                  state.branches[ws.path]!,
                                ).withValues(alpha: 0.15),
                                borderRadius: AppRadius.smallBorderRadius,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((state.changedCount[ws.path] ?? 0) >
                                      0) ...[
                                    Text(
                                      '${state.changedCount[ws.path]}↑',
                                      style: const TextStyle(
                                        fontSize: AppFontSize.xs,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: AppSpacing.xs,
                                    ),
                                  ],
                                  if ((state.behindCount[ws.path] ?? 0) >
                                      0) ...[
                                    Text(
                                      '${state.behindCount[ws.path]}↓',
                                      style: const TextStyle(
                                        fontSize: AppFontSize.xs,
                                        color: Colors.cyan,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: AppSpacing.xs,
                                    ),
                                  ],
                                  Flexible(
                                    child: Text(
                                      state.branches[ws.path]!,
                                      style: TextStyle(
                                        fontSize: AppFontSize.xs,
                                        fontFamily: 'monospace',
                                        color: branchColor(
                                          state.branches[ws.path]!,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        // Project name - prominent
                        Text(
                          ws.name,
                          style: TextStyle(
                            fontSize: nameSize,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        // Quick action buttons
                        if (exists)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: AppSpacing.lg,
                            children: [
                              _gridBtn(
                                icon: GitActionIcons.pull,
                                tooltip: context.l10n.gitPull,
                                onPressed: () => onGitPull(ws),
                                iconSize: btnSize,
                                boxSize: btnBox,
                                color: GitActionColors.pull,
                              ),
                              _gridBtn(
                                icon: GitActionIcons.commit,
                                tooltip: context.l10n.gitCommit,
                                onPressed: () => onGitCommit(ws),
                                iconSize: btnSize,
                                boxSize: btnBox,
                                color: GitActionColors.commit,
                              ),
                              _gridBtn(
                                icon: Icons.folder_open,
                                tooltip: context.l10n.openFolder,
                                onPressed: () => onOpenInFileManager(ws),
                                iconSize: btnSize,
                                boxSize: btnBox,
                              ),
                            ],
                          ),
                      ],
                    ),
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
    BuildContext context,
    Offset position,
    WorkspaceInfo ws,
    bool exists,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'favourite',
          child: Row(
            children: [
              Icon(
                ws.favourite ? Icons.star : Icons.star_border,
                size: AppIconSize.md,
                color: ws.favourite ? Colors.amber : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                ws.favourite
                    ? context.l10n.unfavourite
                    : context.l10n.favourite,
              ),
            ],
          ),
        ),
        if (exists)
          PopupMenuItem(
            value: 'git_pull',
            child: Row(
              children: [
                const Icon(GitActionIcons.pull, size: AppIconSize.md, color: GitActionColors.pull),
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
                const Icon(GitActionIcons.commit, size: AppIconSize.md, color: GitActionColors.commit),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.gitCommit),
              ],
            ),
          ),
        if (exists)
          PopupMenuItem(
            value: 'vscode',
            child: Row(
              children: [
                const Icon(Icons.code, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.openInVscode),
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
        if (ws.hasNginx)
          PopupMenuItem(
            value: 'nginx_remove',
            child: Row(
              children: [
                const Icon(
                  Icons.dns,
                  size: AppIconSize.md,
                  color: Colors.green,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.nginxRemove),
              ],
            ),
          )
        else
          PopupMenuItem(
            value: 'nginx_setup',
            child: Row(
              children: [
                const Icon(Icons.dns, size: AppIconSize.md),
                const SizedBox(width: AppSpacing.sm),
                Text(context.l10n.nginxSetup),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, size: AppIconSize.md),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.edit),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, size: AppIconSize.md, color: Colors.red),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.removeFromList,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
    if (result == null || !context.mounted) return;
    switch (result) {
      case 'favourite':
        onToggleFavourite(ws);
      case 'git_pull':
        onGitPull(ws);
      case 'git_commit':
        onGitCommit(ws);
      case 'vscode':
        onOpenInVscode(ws);
      case 'folder':
        onOpenInFileManager(ws);
      case 'nginx_setup':
        onSetupNginx(ws);
      case 'nginx_remove':
        onRemoveNginx(ws);
      case 'edit':
        onEdit(ws);
      case 'delete':
        onRemove(ws);
    }
  }

  Widget _gridBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required double iconSize,
    required double boxSize,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: boxSize, minHeight: boxSize),
    );
  }
}
