// Unit tests for lib/widgets/pull_rebase_log.dart: the shared mapping from a
// PullRebaseResult to the log line every "Pull (rebase)" dialog prints, and
// whether a follow-up push makes sense. Pure functions — no git needed. The
// `stuckInRebase` line is only reachable through a failed `rebase --abort`,
// which the widget tests cannot trigger deterministically, so it is pinned here.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/services/git_pull_rebase_service.dart';
import 'package:odoo_auto_config/widgets/pull_rebase_log.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  PullRebaseResult r(PullRebaseOutcome o, [int code = 0]) =>
      (outcome: o, exitCode: code);

  group('pullRebaseResultLine', () {
    final cases = <PullRebaseOutcome, (String text, String marker)>{
      PullRebaseOutcome.success: (l10n.gitPullDone, '[+]'),
      PullRebaseOutcome.stashConflict: (l10n.gitPullRebaseStashConflict, '[!]'),
      PullRebaseOutcome.aborted: (l10n.gitPullRebaseAborted, '[-]'),
      PullRebaseOutcome.stuckInRebase: (l10n.gitPullRebaseStuck, '[-]'),
      PullRebaseOutcome.refused: (l10n.gitPullRebaseRefused, '[-]'),
      PullRebaseOutcome.failed: (l10n.gitPullFailed(128), '[-]'),
    };

    test('covers every outcome', () {
      expect(cases.keys.toSet(), PullRebaseOutcome.values.toSet());
    });

    for (final MapEntry(key: outcome, value: (text, marker)) in cases.entries) {
      test('$outcome → its own message and marker', () {
        final line = pullRebaseResultLine(l10n, r(outcome, 128));

        expect(line, contains(text));
        expect(line, contains(marker));
        // No other outcome's message leaks into this line.
        for (final other in cases.entries.where((e) => e.key != outcome)) {
          expect(line, isNot(contains(other.value.$1)),
              reason: '$outcome line must not carry ${other.key} text');
        }
      });
    }

    test('repo prefix in multi-repo logs', () {
      final line =
          pullRebaseResultLine(l10n, r(PullRebaseOutcome.success), repo: 'web');
      expect(line, contains('web: ${l10n.gitPullDone}'));
      expect(pullRebaseResultLine(l10n, r(PullRebaseOutcome.success)),
          isNot(contains(': ${l10n.gitPullDone}')));
    });
  });

  group('pullRebaseRebased', () {
    test('true only for success and stashConflict', () {
      final rebased = {
        for (final o in PullRebaseOutcome.values)
          if (pullRebaseRebased(r(o))) o,
      };
      expect(rebased,
          {PullRebaseOutcome.success, PullRebaseOutcome.stashConflict});
    });
  });
}
