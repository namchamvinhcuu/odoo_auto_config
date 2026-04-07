import 'package:flutter/material.dart';

import 'package:odoo_auto_config/widgets/git_branch_dialog.dart';
import 'repo_git_pull_dialog.dart';
import 'repo_commit_dialog.dart';
import 'repo_create_pr_dialog.dart';
import 'repo_prune_dialog.dart';

// ── Repo Branch Dialog (full git management per repo) ──

class RepoBranchDialog extends StatelessWidget {
  final String repoName;
  final String repoPath;
  final String currentBranch;
  final Color Function(String) branchColor;
  final void Function(String branch) onChanged;

  const RepoBranchDialog({
    super.key,
    required this.repoName,
    required this.repoPath,
    required this.currentBranch,
    required this.branchColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GitBranchDialog(
      path: repoPath,
      displayName: repoName,
      currentBranch: currentBranch,
      branchColor: branchColor,
      onChanged: onChanged,
      pullDialogBuilder: (name, path, {targetBranch, currentBranch}) =>
          RepoGitPullDialog(
        repoName: name,
        repoPath: path,
        targetBranch: targetBranch,
        currentBranch: currentBranch,
      ),
      commitDialogBuilder: (name, path) => RepoCommitDialog(
        repoName: name,
        repoPath: path,
      ),
      prDialogBuilder: (name, path, currentBranch) => RepoCreatePRDialog(
        repoName: name,
        repoPath: path,
        currentBranch: currentBranch,
      ),
      pruneDialogBuilder: (branches) => RepoPruneDialog(branches: branches),
    );
  }
}
