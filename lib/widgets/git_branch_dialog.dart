import 'package:flutter/material.dart';

import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';

/// Callback to build a sub-dialog widget.
/// [name] is the display name, [path] is the working directory.
typedef GitDialogBuilder = Widget Function(String name, String path);

/// Callback to build a pull dialog with optional target/current branch.
typedef GitPullDialogBuilder = Widget Function(
  String name,
  String path, {
  String? targetBranch,
  String? currentBranch,
});

/// Callback to build a PR dialog with current branch info.
typedef GitPRDialogBuilder = Widget Function(
  String name,
  String path,
  String currentBranch,
);

/// Callback to build a prune dialog that returns branches to delete.
typedef GitPruneDialogBuilder = Widget Function(List<String> branches);

/// Unified Git Branches dialog used by both Other Projects and Odoo Workspace.
///
/// All git logic is shared; sub-dialogs (pull, commit, PR, prune) are injected
/// via builder callbacks so each context can use its own dialog implementation.
class GitBranchDialog extends StatefulWidget {
  final String path;
  final String displayName;
  final String currentBranch;
  final Color Function(String) branchColor;
  final void Function(String branch) onChanged;

  // Sub-dialog builders
  final GitPullDialogBuilder pullDialogBuilder;
  final GitDialogBuilder commitDialogBuilder;
  final GitPRDialogBuilder prDialogBuilder;
  final GitPruneDialogBuilder pruneDialogBuilder;

  const GitBranchDialog({
    super.key,
    required this.path,
    required this.displayName,
    required this.currentBranch,
    required this.branchColor,
    required this.onChanged,
    required this.pullDialogBuilder,
    required this.commitDialogBuilder,
    required this.prDialogBuilder,
    required this.pruneDialogBuilder,
  });

  @override
  State<GitBranchDialog> createState() => _GitBranchDialogState();
}

class _GitBranchDialogState extends State<GitBranchDialog> {
  List<String> _local = [];
  List<String> _remote = [];
  String _current = '';
  bool _loading = true;
  bool _switching = false;
  String? _message;
  bool _isError = false;
  int _changedFiles = 0;
  int _behindRemote = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.currentBranch;
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _loading = true);
    final result = await GitBranchService.loadBranches(widget.path);
    if (!mounted) return;
    setState(() {
      _local = result.local
        ..sort((a, b) {
          if (a == _current) return -1;
          if (b == _current) return 1;
          return a.compareTo(b);
        });
      _remote = result.remote..sort();
      _changedFiles = result.changedFiles;
      _behindRemote = result.behindRemote;
      _loading = false;
    });
  }

  Future<void> _checkout(String branch) async {
    setState(() {
      _switching = true;
      _message = null;
    });
    final result = await GitBranchService.switchBranch(widget.path, branch);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _current = branch;
        _switching = false;
        _message = result.output;
        _isError = false;
      });
      widget.onChanged(branch);
      _loadBranches();
    } else {
      setState(() {
        _switching = false;
        _message = result.output;
        _isError = true;
      });
    }
  }

  Future<void> _createBranch() async {
    final controller = TextEditingController();
    final allBranches = [..._local, ..._remote.map((r) => 'origin/$r')];
    var selectedBase = _current;
    final result2 = await AppDialog.show<({String name, String base})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final hasName = controller.text.trim().isNotEmpty;
            return AlertDialog(
              title: Row(
                children: [
                  Text(ctx.l10n.gitBranchCreateTitle),
                  const Spacer(),
                  AppDialog.closeButton(ctx),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: ctx.l10n.gitBranchNameLabel,
                      hintText: ctx.l10n.gitBranchNameHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        Navigator.pop(
                            ctx, (name: v.trim(), base: selectedBase));
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBase,
                    decoration: InputDecoration(
                      labelText: ctx.l10n.gitBranchBaseBranch,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    items: allBranches
                        .map(
                            (b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => selectedBase = v);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: hasName
                      ? () {
                          Navigator.pop(ctx,
                              (name: controller.text.trim(), base: selectedBase));
                        }
                      : null,
                  child: Text(ctx.l10n.gitBranchCreate),
                ),
              ],
            );
          },
        ),
    );
    controller.dispose();
    if (result2 == null || !mounted) return;

    final baseBranch =
        result2.base == _current ? null : result2.base;
    final result = await GitBranchService.createBranch(
      widget.path,
      result2.name,
      baseBranch: baseBranch,
    );
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _current = result2.name;
        _message = result.output;
        _isError = false;
      });
      widget.onChanged(result2.name);
      _loadBranches();
    } else {
      setState(() {
        _message = result.output;
        _isError = true;
      });
    }
  }

  Future<void> _deleteBranch(String branch) async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(ctx.l10n.gitBranchDeleteTitle),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
        content: Text(ctx.l10n.gitBranchDeleteConfirm(branch)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await GitBranchService.deleteBranch(widget.path, branch);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _message = result.output;
        _isError = false;
      });
      _loadBranches();
    } else {
      if (GitBranchService.isNotFullyMergedError(result.output)) {
        if (!mounted) return;
        final force = await AppDialog.show<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Text(ctx.l10n.gitBranchForceDeleteTitle),
                const Spacer(),
                AppDialog.closeButton(ctx),
              ],
            ),
            content: Text(ctx.l10n.gitBranchForceDeleteConfirm(branch)),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: Text(ctx.l10n.gitBranchForceDelete),
              ),
            ],
          ),
        );
        if (force == true && mounted) {
          final forceResult = await GitBranchService.deleteBranch(
            widget.path,
            branch,
            force: true,
          );
          if (mounted) {
            setState(() {
              _message = forceResult.output;
              _isError = !forceResult.success;
            });
            if (forceResult.success) _loadBranches();
          }
        }
      } else {
        setState(() {
          _message = result.output;
          _isError = true;
        });
      }
    }
  }

  Future<void> _mergeBranch(String branch) async {
    final direction = await AppDialog.show<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Text(ctx.l10n.gitBranchMerge),
            const Spacer(),
            AppDialog.closeButton(ctx),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_back, color: Colors.blue),
              title: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Merge '),
                TextSpan(
                  text: branch,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const TextSpan(text: ' into '),
                TextSpan(
                  text: _current,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ])),
              subtitle:
                  Text(ctx.l10n.gitMergeIntoCurrentDesc(_current, branch)),
              onTap: () => Navigator.pop(ctx, 'into_current'),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mediumBorderRadius,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.arrow_forward, color: Colors.green),
              title: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Merge '),
                TextSpan(
                  text: _current,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const TextSpan(text: ' into '),
                TextSpan(
                  text: branch,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ])),
              subtitle:
                  Text(ctx.l10n.gitMergeIntoTargetDesc(_current, branch)),
              onTap: () => Navigator.pop(ctx, 'into_target'),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mediumBorderRadius,
              ),
            ),
          ],
        ),
      ),
    );
    if (direction == null || !mounted) return;

    setState(() {
      _switching = true;
      _message = null;
    });

    try {
      final MergeResult result;
      if (direction == 'into_current') {
        result = await GitBranchService.mergeIntoCurrent(
          widget.path,
          branch,
          _current,
        );
      } else {
        result = await GitBranchService.mergeIntoTarget(
          widget.path,
          _current,
          branch,
        );
      }
      if (!mounted) return;
      setState(() {
        _current = result.currentBranch;
        _switching = false;
        _message = result.output;
        _isError = !result.success;
      });
      widget.onChanged(result.currentBranch);
      if (direction == 'into_target') _loadBranches();
    } catch (e) {
      if (mounted) {
        setState(() {
          _switching = false;
          _message = e.toString();
          _isError = true;
        });
      }
    }
  }

  Future<void> _publishBranch(String branch) async {
    setState(() {
      _switching = true;
      _message = null;
    });
    final result = await GitBranchService.publishBranch(widget.path, branch);
    if (!mounted) return;
    setState(() {
      _switching = false;
      _message = result.output;
      _isError = !result.success;
    });
    if (result.success) _loadBranches();
  }

  Future<void> _pullBranch(String branch) async {
    await AppDialog.show(
      context: context,
      builder: (ctx) => widget.pullDialogBuilder(
        widget.displayName,
        widget.path,
        targetBranch: branch,
        currentBranch: _current,
      ),
    );
    if (mounted) {
      setState(() => _message = null);
      _loadBranches();
    }
  }

  Future<void> _pruneCheck() async {
    setState(() {
      _switching = true;
      _message = null;
    });
    final result = await GitBranchService.cleanStaleBranches(
      widget.path,
      currentBranch: _current,
    );
    if (!mounted) return;

    if (result.staleBranches.isEmpty) {
      setState(() {
        _switching = false;
        _message = result.output;
        _isError = false;
      });
      return;
    }

    setState(() => _switching = false);

    if (!mounted) return;
    final toDelete = await AppDialog.show<List<String>>(
      context: context,
      builder: (ctx) => widget.pruneDialogBuilder(result.staleBranches),
    );
    if (toDelete == null || toDelete.isEmpty || !mounted) return;

    final deleteResult =
        await GitBranchService.deleteBranches(widget.path, toDelete);
    if (mounted) {
      setState(() {
        if (deleteResult.deleted.isNotEmpty) {
          _message = 'Deleted: ${deleteResult.deleted.join(', ')}';
          _isError = false;
        }
        if (deleteResult.failed.isNotEmpty) {
          _message =
              '${_message ?? ''}${_message != null ? '\n' : ''}Failed: ${deleteResult.failed.join(', ')}';
          _isError =
              deleteResult.failed.isNotEmpty && deleteResult.deleted.isEmpty;
        }
      });
      _loadBranches();
    }
  }

  // ── Build helpers ──

  List<Widget> _buildBranchListWithDivider(
    List<String> branches, {
    bool isRemote = false,
  }) {
    final mainBranches =
        branches.where((b) => b == 'main' || b == 'master').toList();
    final otherBranches =
        branches.where((b) => b != 'main' && b != 'master').toList();
    return [
      ...otherBranches.map((b) => _branchTile(b, isRemote: isRemote)),
      if (otherBranches.isNotEmpty && mainBranches.isNotEmpty)
        const Divider(height: AppSpacing.md),
      ...mainBranches.map((b) => _branchTile(b, isRemote: isRemote)),
    ];
  }

  Widget _branchTile(String branch, {bool isRemote = false}) {
    final isCurrent = !isRemote && branch == _current;
    final canTap = !isCurrent && !_switching;
    return InkWell(
      onTap: canTap ? () => _checkout(branch) : null,
      mouseCursor:
          canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
      borderRadius: AppRadius.smallBorderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.check_circle : Icons.circle_outlined,
              size: AppIconSize.lg,
              color: isCurrent ? widget.branchColor(branch) : Colors.grey,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                branch,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.xl,
                  fontWeight: isCurrent ? FontWeight.bold : null,
                  color: isCurrent ? widget.branchColor(branch) : null,
                ),
              ),
            ),
            if (isRemote)
              Icon(
                Icons.cloud_outlined,
                size: AppIconSize.md,
                color: Colors.grey.shade500,
              ),
            if (!isRemote && isCurrent && !_remote.contains(branch))
              IconButton(
                onPressed: _switching ? null : () => _publishBranch(branch),
                icon: const Icon(
                  GitActionIcons.publish,
                  size: AppIconSize.md,
                  color: GitActionColors.publish,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppIconSize.xl,
                  minHeight: AppIconSize.xl,
                ),
                tooltip: context.l10n.gitBranchPublish(branch),
              ),
            if (!isRemote && !isCurrent) ...[
              if (!_remote.contains(branch))
                IconButton(
                  onPressed: _switching ? null : () => _publishBranch(branch),
                  icon: const Icon(
                    GitActionIcons.publish,
                    size: AppIconSize.md,
                    color: GitActionColors.publish,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppIconSize.xl,
                    minHeight: AppIconSize.xl,
                  ),
                  tooltip: context.l10n.gitBranchPublish(branch),
                ),
              IconButton(
                onPressed: _switching ? null : () => _pullBranch(branch),
                icon: const Icon(
                  GitActionIcons.pull,
                  size: AppIconSize.md,
                  color: GitActionColors.pull,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppIconSize.xl,
                  minHeight: AppIconSize.xl,
                ),
                tooltip: context.l10n.gitBranchPullBranch(branch),
              ),
              IconButton(
                onPressed: _switching ? null : () => _mergeBranch(branch),
                icon: const Icon(
                  GitActionIcons.pr,
                  size: AppIconSize.md,
                  color: GitActionColors.pr,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppIconSize.xl,
                  minHeight: AppIconSize.xl,
                ),
                tooltip: context.l10n.gitBranchMerge,
              ),
              if (branch != 'main' && branch != 'master')
                IconButton(
                  onPressed: _switching ? null : () => _deleteBranch(branch),
                  icon: const Icon(
                    GitActionIcons.delete,
                    size: AppIconSize.md,
                    color: GitActionColors.delete,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppIconSize.xl,
                    minHeight: 24,
                  ),
                  tooltip: context.l10n.gitBranchDeleteBranch,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.account_tree,
                size: AppIconSize.md, color: Colors.grey.shade500),
            const SizedBox(width: AppSpacing.sm),
            Text(
              context.l10n.gitBranchLocal,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._buildBranchListWithDivider(_local, isRemote: false),
      ],
    );
  }

  Widget _buildRemoteColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.cloud_outlined,
                size: AppIconSize.md, color: Colors.grey.shade500),
            const SizedBox(width: AppSpacing.sm),
            Text(
              context.l10n.gitBranchRemote,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._buildBranchListWithDivider(_remote, isRemote: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitBranches),
          if (_current.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Chip(
              avatar: Icon(
                Icons.check_circle,
                size: AppIconSize.md,
                color: widget.branchColor(_current),
              ),
              label: Text(
                _current,
                style: TextStyle(
                  color: widget.branchColor(_current),
                  fontFamily: 'monospace',
                  fontSize: AppFontSize.md,
                ),
              ),
              backgroundColor:
                  widget.branchColor(_current).withValues(alpha: 0.1),
              visualDensity: VisualDensity.compact,
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          TextButton.icon(
            onPressed: _switching ? null : _pruneCheck,
            icon: const Icon(Icons.cleaning_services, size: AppIconSize.md),
            label: Text(context.l10n.gitBranchCleanStale),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton.icon(
            onPressed: _switching
                ? null
                : () async {
                    final url =
                        await GitBranchService.getRemoteUrl(widget.path);
                    if (url != null) {
                      final branch = _current;
                      final isDefault =
                          branch == 'main' || branch == 'master';
                      final target =
                          isDefault ? url : '$url/tree/$branch';
                      await GitBranchService.openInBrowser(target);
                    }
                  },
            icon: const Icon(Icons.open_in_new, size: AppIconSize.md),
            label: Text(context.l10n.gitViewOnGithub),
          ),
          const Spacer(),
          IconButton(
            onPressed: (_switching || _loading)
                ? null
                : () {
                    setState(() => _message = null);
                    _loadBranches();
                  },
            icon: const Icon(Icons.refresh, color: Colors.white, size: AppIconSize.md),
            tooltip: context.l10n.refresh,
            style: IconButton.styleFrom(
              backgroundColor: (_switching || _loading) ? Colors.grey : GitActionColors.refresh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppDialog.closeButton(context, enabled: !_switching),
        ],
      ),
      content: Builder(
        builder: (context) {
          final isWide = MediaQuery.of(context).size.width > 900;
          return SizedBox(
            width: isWide ? AppDialog.widthLg : AppDialog.widthMd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Action bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: (_switching ||
                              _loading ||
                              _behindRemote == 0)
                          ? null
                          : () async {
                              await AppDialog.show(
                                context: context,
                                builder: (ctx) => widget.pullDialogBuilder(
                                  widget.displayName,
                                  widget.path,
                                ),
                              );
                              if (mounted) {
                                setState(() => _message = null);
                                _loadBranches();
                              }
                            },
                      icon: const Icon(GitActionIcons.pull, size: AppIconSize.md),
                      label: Text(context.l10n.gitBranchPull),
                      style: FilledButton.styleFrom(
                        foregroundColor: GitActionColors.pull,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: (_switching ||
                              _loading ||
                              _changedFiles == 0)
                          ? null
                          : () async {
                              await AppDialog.show(
                                context: context,
                                builder: (ctx) => widget.commitDialogBuilder(
                                  widget.displayName,
                                  widget.path,
                                ),
                              );
                              if (mounted) {
                                setState(() => _message = null);
                                _loadBranches();
                              }
                            },
                      icon: const Icon(GitActionIcons.commit, size: AppIconSize.md),
                      label: Text(context.l10n.gitBranchCommit),
                      style: FilledButton.styleFrom(
                        foregroundColor: GitActionColors.commit,
                      ),
                    ),
                    // PR button — hidden, code kept for future use
                    // if (_current != 'main' && _current != 'master') ...[
                    //   const SizedBox(width: AppSpacing.sm),
                    //   FilledButton.tonalIcon(
                    //     onPressed: _switching
                    //         ? null
                    //         : () async {
                    //             await AppDialog.show(
                    //               context: context,
                    //               builder: (ctx) => widget.prDialogBuilder(
                    //                 widget.displayName,
                    //                 widget.path,
                    //                 _current,
                    //               ),
                    //             );
                    //             if (mounted) {
                    //               setState(() => _message = null);
                    //               _loadBranches();
                    //             }
                    //           },
                    //     icon: const Icon(GitActionIcons.prBar,
                    //         size: AppIconSize.md),
                    //     label: Text(context.l10n.gitBranchPR),
                    //     style: FilledButton.styleFrom(
                    //       foregroundColor: GitActionColors.pr,
                    //     ),
                    //   ),
                    // ],
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _switching ? null : _createBranch,
                      icon: const Icon(Icons.add, size: AppIconSize.md),
                      label: Text(context.l10n.gitBranchCreate),
                    ),
                  ],
                ),
                // Status info
                if (!_loading &&
                    (_changedFiles > 0 || _behindRemote > 0)) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (_changedFiles > 0)
                        Chip(
                          avatar: const Icon(Icons.edit_note,
                              size: AppIconSize.md, color: Colors.orange),
                          label: Text(
                            context.l10n.gitBranchChanged(_changedFiles),
                            style: const TextStyle(color: Colors.orange),
                          ),
                          backgroundColor:
                              Colors.orange.withValues(alpha: 0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (_changedFiles > 0 && _behindRemote > 0)
                        const SizedBox(width: AppSpacing.sm),
                      if (_behindRemote > 0)
                        Chip(
                          avatar: const Icon(Icons.arrow_downward,
                              size: AppIconSize.md, color: Colors.cyan),
                          label: Text(
                            context.l10n.gitBranchBehind(_behindRemote),
                            style: const TextStyle(color: Colors.cyan),
                          ),
                          backgroundColor: Colors.cyan.withValues(alpha: 0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_switching)
                  const Center(child: CircularProgressIndicator())
                else if (isWide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildLocalColumn()),
                        if (_remote.isNotEmpty) ...[
                          const VerticalDivider(width: AppSpacing.xxl),
                          Expanded(child: _buildRemoteColumn()),
                        ],
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLocalColumn(),
                      if (_remote.isNotEmpty) ...[
                        const Divider(height: AppSpacing.xxl),
                        _buildRemoteColumn(),
                      ],
                    ],
                  ),
                if (_message != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color:
                          (_isError ? Colors.red : Colors.green).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: AppRadius.smallBorderRadius,
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _isError ? Colors.red : Colors.green,
                        fontFamily: 'monospace',
                        fontSize: AppFontSize.md,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
