import 'package:odoo_auto_config/services/git_branch_service.dart';

/// Data class for a single repo inside addons/
class RepoInfo {
  final String name;
  final String path;
  String branch = '';
  int changedFiles = 0;
  int aheadCount = 0;
  int behindCount = 0;
  bool hasUpstream = true;

  /// Commits on a branch that exists on no remote yet — the number behind the
  /// Publish affordance. Always measured through
  /// [GitBranchService.loadPublishableCount], never counted here.
  int unpublishedCount = 0;

  bool fetchFailed = false;
  bool selected = false;
  bool loaded = false;

  /// True while the background `git fetch` + behind-count refresh is running
  /// (phase 2). The tile shows local status immediately (phase 1) and a small
  /// spinner until the fresh remote counts arrive.
  bool syncing = false;

  RepoInfo({
    required this.name,
    required this.path,
  });

  /// Store a freshly measured status, overwriting **all four** fields.
  ///
  /// Instances are mutable and reused across refreshes, so a partial update would
  /// leave the previous branch's numbers on screen — that is exactly how the
  /// stale "unpushed commits" badge survived a branch switch. Keeping the writes
  /// in one public method also makes them testable without mounting the dialog.
  ///
  /// [unpublishedCount] is required rather than optional on purpose: it belongs to
  /// the same reset. A branch that just gained an upstream (the user published it)
  /// has nothing unpublished any more, so a caller that updates the divergence
  /// without clearing this number would leave the Publish badge on a branch that
  /// now needs Push instead — the same clobber bug, one field over.
  void applyDivergence(
    UpstreamDivergence divergence, {
    required int unpublishedCount,
  }) {
    aheadCount = divergence.ahead;
    behindCount = divergence.behind;
    hasUpstream = divergence.hasUpstream;
    this.unpublishedCount = unpublishedCount;
  }
}
