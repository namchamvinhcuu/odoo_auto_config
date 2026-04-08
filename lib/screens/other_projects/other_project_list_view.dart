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
    required this.onLinkNginx,
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
  final ValueChanged<WorkspaceInfo> onLinkNginx;
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
                    if (ws.description.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Chip(
                          label: Text(
                            ws.description,
                            overflow: TextOverflow.ellipsis,
                          ),
                          avatar: const Icon(
                            Icons.description,
                            size: AppIconSize.md,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
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
                    if (state.branches.containsKey(ws.path)) ...[
                      InkWell(
                        onTap: () => onSwitchBranch(ws),
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(8),
                        child: Chip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state.branches[ws.path]!,
                                style: TextStyle(
                                  color: branchColor(state.branches[ws.path]!),
                                ),
                              ),
                              if ((state.changedCount[ws.path] ?? 0) > 0) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  '${state.changedCount[ws.path]}↑',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                              if ((state.behindCount[ws.path] ?? 0) > 0) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  '${state.behindCount[ws.path]}↓',
                                  style: const TextStyle(
                                    color: Colors.cyan,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          avatar: Icon(
                            Icons.account_tree,
                            size: AppIconSize.md,
                            color: branchColor(state.branches[ws.path]!),
                          ),
                          backgroundColor: branchColor(
                            state.branches[ws.path]!,
                          ).withValues(alpha: 0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
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
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.dns),
                        tooltip: context.l10n.nginxSetup,
                        onSelected: (v) {
                          if (v == 'setup') onSetupNginx(ws);
                          if (v == 'link') onLinkNginx(ws);
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'setup',
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: AppIconSize.md),
                                const SizedBox(width: AppSpacing.sm),
                                Text(context.l10n.nginxSetup),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'link',
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: AppIconSize.md),
                                const SizedBox(width: AppSpacing.sm),
                                Text(context.l10n.nginxLink),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
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
