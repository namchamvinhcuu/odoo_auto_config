import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';

import 'repo_info.dart';

/// One row of the Odoo Workspace repo list.
///
/// Lives outside `odoo_workspace_dialog.dart` on purpose. It used to be a
/// private builder of a private State class, so the rules deciding *which git
/// buttons appear* could not be tested at all: Dart privacy is per-file, and
/// mounting the dialog to reach them drags in a real filesystem scan, real
/// `StorageService` reads and a real `git fetch`. Three separate bugs in this
/// exact spot shipped because of that blind spot (missing Push affordance,
/// stale counts with no upstream, Push showing with nothing to push).
///
/// Stateless and fed only by [repo] + callbacks — same shape as
/// `OtherProjectGridView` — so a widget test can pump it directly. The dialog
/// keeps ownership of `setState`, selection persistence and dialog navigation.
class RepoTile extends StatelessWidget {
  const RepoTile({
    super.key,
    required this.repo,
    required this.branchColor,
    required this.onSelectedChanged,
    required this.onOpenInVscode,
    required this.onOpenBranchDialog,
    required this.onPull,
    required this.onPublish,
    required this.onPush,
    required this.onCreatePr,
    required this.onRemove,
  });

  final RepoInfo repo;

  /// Branch-name → colour mapping, owned by the dialog so the branch chip here
  /// and the branch dialog stay in the same palette.
  final Color Function(String) branchColor;

  final ValueChanged<bool> onSelectedChanged;
  final VoidCallback onOpenInVscode;
  final VoidCallback onOpenBranchDialog;
  final VoidCallback onPull;
  final VoidCallback onPublish;
  final VoidCallback onPush;
  final VoidCallback onCreatePr;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: () => onSelectedChanged(!repo.selected),
        // NO onDoubleTap here. A double-tap recognizer on the row holds the
        // gesture arena for every pointer inside it, including the git buttons:
        // they then only fire ~300ms later (kDoubleTapTimeout), and two quick
        // taps on different buttons get merged into one double-tap that runs
        // *this* callback instead of the button pressed. Open-in-VSCode lives on
        // the repo name below, where there is nothing else to hit.
        borderRadius: AppRadius.mediumBorderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // Checkbox
              Checkbox(
                value: repo.selected,
                onChanged: (v) => onSelectedChanged(v ?? false),
              ),
              const SizedBox(width: AppSpacing.md),
              // Repo name — also the double-tap target for "open in VSCode"
              // (see the note on the row InkWell above).
              Expanded(
                flex: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onOpenInVscode,
                  child: Text(
                    repo.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: AppFontSize.lg,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Loading placeholder or status
              if (!repo.loaded)
                const SizedBox(
                  width: AppIconSize.md,
                  height: AppIconSize.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                // Branch chip (clickable → open branch dialog)
                if (repo.branch.isNotEmpty)
                  InkWell(
                    onTap: onOpenBranchDialog,
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: AppRadius.smallBorderRadius,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: branchColor(
                          repo.branch,
                        ).withValues(alpha: 0.15),
                        borderRadius: AppRadius.smallBorderRadius,
                      ),
                      child: Text(
                        repo.branch,
                        style: TextStyle(
                          fontSize: AppFontSize.md,
                          fontFamily: 'monospace',
                          color: branchColor(repo.branch),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.md),
                // Status indicators
                if (repo.syncing)
                  const Padding(
                    padding: EdgeInsets.only(right: AppSpacing.sm),
                    child: SizedBox(
                      width: AppIconSize.sm,
                      height: AppIconSize.sm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (repo.fetchFailed)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Tooltip(
                      message: context.l10n.gitFetchFailed,
                      child: const Icon(
                        Icons.sync_problem,
                        size: AppIconSize.md,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                if (repo.changedFiles > 0)
                  _statusBadge(
                    '${repo.changedFiles} ${GitSyncBadge.changed}',
                    GitSyncBadge.changedColor,
                  ),
                if (repo.hasUpstream && repo.aheadCount > 0)
                  _statusBadge(
                    '${repo.aheadCount}',
                    GitSyncBadge.aheadColor,
                    icon: GitSyncBadge.ahead,
                    tooltip: context.l10n.gitBranchAhead(repo.aheadCount),
                  ),
                if (repo.behindCount > 0)
                  _statusBadge(
                    '${repo.behindCount} ${GitSyncBadge.behind}',
                    GitSyncBadge.behindColor,
                  ),
                // Branch that exists on no remote yet: `ahead` is 0 there, so
                // without this the tile would show nothing for a brand-new
                // branch full of work. Same badge as the Other Projects cards.
                if (repo.unpublishedCount > 0)
                  _statusBadge(
                    '${repo.unpublishedCount}',
                    GitSyncBadge.unpublishedColor,
                    icon: GitSyncBadge.unpublished,
                    tooltip: context.l10n.gitBranchUnpublished(
                      repo.unpublishedCount,
                    ),
                  ),
                // Per-repo actions
                const SizedBox(width: AppSpacing.md),
                _repoActionButton(
                  icon: GitActionIcons.pull,
                  tooltip: context.l10n.gitPull,
                  color: GitActionColors.pull,
                  onPressed: onPull,
                ),
                if (!repo.hasUpstream) ...[
                  // Only when there is something to publish — parity with the
                  // Other Projects cards, which drive this off the same count.
                  //
                  // This hides the button in a case where Publish would still
                  // WORK: `publishBranch` runs `commit --allow-empty`, so a
                  // branch with 0 unpublished commits can be published and get
                  // its remote branch (same for a repo whose commits live on a
                  // non-origin remote, which `--not --remotes` counts as 0).
                  // The trade is deliberate — fewer buttons on a dense row, and
                  // that case keeps two other routes: the branch chip → Git
                  // Branches dialog, and the bulk Publish button on the toolbar.
                  // Do not "fix" this into `!hasUpstream` alone: that is how the
                  // tile used to offer Publish on a detached HEAD or a repo with
                  // no remote, where it fails outright.
                  if (repo.unpublishedCount > 0)
                    _repoActionButton(
                      icon: GitActionIcons.publish,
                      tooltip: context.l10n.gitBranchPublish(repo.branch),
                      color: GitActionColors.publish,
                      onPressed: onPublish,
                    ),
                ] else ...[
                  // Push only when there is something to push — same rule as the
                  // Other Projects cards. PR stays available regardless.
                  // Icon/color left as-is: #3 only changed WHEN this shows. Using
                  // the ahead badge glyph here would make it identical to the
                  // Publish button two lines up.
                  if (repo.aheadCount > 0)
                    _repoActionButton(
                      icon: GitActionIcons.push,
                      tooltip: context.l10n.push,
                      color: GitActionColors.push,
                      onPressed: onPush,
                    ),
                  _repoActionButton(
                    icon: GitActionIcons.pr,
                    tooltip: context.l10n.gitBranchPR,
                    color: GitActionColors.pr,
                    onPressed: onCreatePr,
                  ),
                ],
              ],
              // Remove from workspace (always visible)
              _repoActionButton(
                icon: Icons.close,
                tooltip: context.l10n.removeFromList,
                color: GitActionColors.delete,
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [icon] and [tooltip] are optional: the "unpushed commits" badge needs a
  /// glyph of its own because the changed-files badge already uses "N ↑".
  Widget _statusBadge(
    String text,
    Color color, {
    IconData? icon,
    String? tooltip,
  }) {
    Widget badge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.smallBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppFontSize.md, color: color),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: AppFontSize.sm,
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (tooltip != null) {
      badge = Tooltip(message: tooltip, child: badge);
    }
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: badge,
    );
  }

  Widget _repoActionButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: AppIconSize.lg,
        color: onPressed != null ? color : null,
      ),
      tooltip: tooltip,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}
