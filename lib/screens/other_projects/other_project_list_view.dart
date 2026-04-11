import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';

class OtherProjectListView extends StatelessWidget {
  const OtherProjectListView({
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
    required this.iconForType,
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
  final IconData Function(String) iconForType;
  final Color Function(String) colorForType;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: workspaces.length,
      itemBuilder: (context, index) {
        final ws = workspaces[index];
        final exists = Directory(ws.path).existsSync();

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
                      exists ? iconForType(ws.type) : Icons.folder_off,
                      color: exists ? colorForType(ws.type) : Colors.grey,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        ws.name,
                        style: const TextStyle(
                          fontSize: AppFontSize.lg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (ws.type.isNotEmpty)
                      Chip(
                        label: Text(ws.type),
                        avatar: Icon(
                          iconForType(ws.type),
                          size: AppIconSize.md,
                          color: colorForType(ws.type),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  ws.path,
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
                      onPressed: () => onToggleFavourite(ws),
                      icon: Icon(
                        ws.favourite ? Icons.star : Icons.star_border,
                        color: ws.favourite ? Colors.amber : null,
                      ),
                      tooltip: ws.favourite
                          ? context.l10n.unfavourite
                          : context.l10n.favourite,
                    ),
                    if (exists) ...[
                      IconButton(
                        onPressed: () => onGitPull(ws),
                        icon: const Icon(GitActionIcons.pull, color: GitActionColors.pull),
                        tooltip: context.l10n.gitPull,
                      ),
                      IconButton(
                        onPressed: () => onGitCommit(ws),
                        icon: const Icon(GitActionIcons.commit, color: GitActionColors.commit),
                        tooltip: context.l10n.gitCommit,
                      ),
                      IconButton(
                        onPressed: () => onOpenInVscode(ws),
                        icon: const Icon(Icons.code),
                        tooltip: context.l10n.openInVscode,
                      ),
                      IconButton(
                        onPressed: () => onOpenInFileManager(ws),
                        icon: const Icon(Icons.folder_open),
                        tooltip: context.l10n.openFolder,
                      ),
                    ],
                    IconButton(
                      onPressed: () => onEdit(ws),
                      icon: const Icon(Icons.edit),
                      tooltip: context.l10n.edit,
                    ),
                    if (ws.hasNginx)
                      IconButton(
                        onPressed: () => onRemoveNginx(ws),
                        icon: const Icon(Icons.dns, color: Colors.green),
                        tooltip: context.l10n.nginxRemove,
                      )
                    else
                      IconButton(
                        onPressed: () => onSetupNginx(ws),
                        icon: const Icon(Icons.dns),
                        tooltip: context.l10n.nginxSetup,
                      ),
                    if (state.branches.containsKey(ws.path)) ...[
                      const SizedBox(width: AppSpacing.xs),
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
                              if ((state.changedCount[ws.path] ?? 0) > 0) ...[
                                Text(
                                  '${state.changedCount[ws.path]}↑',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                              ],
                              if ((state.behindCount[ws.path] ?? 0) > 0) ...[
                                Text(
                                  '${state.behindCount[ws.path]}↓',
                                  style: const TextStyle(
                                    color: Colors.cyan,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                              ],
                              Text(
                                state.branches[ws.path]!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  color: branchColor(state.branches[ws.path]!),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (ws.description.isNotEmpty)
                      Text(
                        ws.description,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.sm,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    IconButton(
                      onPressed: () => onRemove(ws),
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
