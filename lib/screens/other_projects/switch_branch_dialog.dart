import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:odoo_auto_config/widgets/git_branch_dialog.dart';
import 'create_pr_dialog.dart';
import 'prune_dialog.dart';
import 'simple_git_commit_dialog.dart';
import 'simple_git_pull_dialog.dart';

class SwitchBranchDialog extends StatelessWidget {
  final String projectPath;
  final String currentBranch;
  final Color Function(String) branchColor;
  final void Function(String branch) onSwitched;

  const SwitchBranchDialog({
    super.key,
    required this.projectPath,
    required this.currentBranch,
    required this.branchColor,
    required this.onSwitched,
  });

  @override
  Widget build(BuildContext context) {
    return GitBranchDialog(
      path: projectPath,
      displayName: p.basename(projectPath),
      currentBranch: currentBranch,
      branchColor: branchColor,
      onChanged: onSwitched,
      pullDialogBuilder: (name, path, {targetBranch, currentBranch}) =>
          SimpleGitPullDialog(
        projectName: name,
        projectPath: path,
        targetBranch: targetBranch,
        currentBranch: currentBranch,
      ),
      commitDialogBuilder: (name, path) => SimpleGitCommitDialog(
        projectName: name,
        projectPath: path,
      ),
      prDialogBuilder: (name, path, currentBranch) => CreatePRDialog(
        projectName: name,
        projectPath: path,
        currentBranch: currentBranch,
      ),
      pruneDialogBuilder: (branches) => PruneDialog(branches: branches),
    );
  }
}
