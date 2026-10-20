import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/services/git_pull_rebase_service.dart';

/// Whether the branch's commits ended up on top of the remote, so a follow-up
/// push makes sense. True for [PullRebaseOutcome.stashConflict] too: only the
/// uncommitted changes conflicted, the commits themselves rebased fine.
bool pullRebaseRebased(PullRebaseResult result) =>
    result.outcome == PullRebaseOutcome.success ||
    result.outcome == PullRebaseOutcome.stashConflict;

/// ANSI log line describing [result], shared by every dialog that offers
/// "Pull (rebase)". [repo] prefixes the line in multi-repo logs.
String pullRebaseResultLine(
  AppLocalizations l10n,
  PullRebaseResult result, {
  String? repo,
}) {
  final prefix = repo == null ? '' : '$repo: ';
  return switch (result.outcome) {
    PullRebaseOutcome.success =>
      '\x1B[0;32m[+] $prefix${l10n.gitPullDone}\x1B[0m',
    PullRebaseOutcome.stashConflict =>
      '\x1B[0;33m[!] $prefix${l10n.gitPullRebaseStashConflict}\x1B[0m',
    PullRebaseOutcome.aborted =>
      '\x1B[0;31m[-] $prefix${l10n.gitPullRebaseAborted}\x1B[0m',
    PullRebaseOutcome.stuckInRebase =>
      '\x1B[0;31m[-] $prefix${l10n.gitPullRebaseStuck}\x1B[0m',
    PullRebaseOutcome.refused =>
      '\x1B[0;31m[-] $prefix${l10n.gitPullRebaseRefused}\x1B[0m',
    PullRebaseOutcome.failed =>
      '\x1B[0;31m[-] $prefix${l10n.gitPullFailed(result.exitCode)}\x1B[0m',
  };
}
