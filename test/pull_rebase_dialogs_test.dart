// Widget tests for the "Pull (rebase)" recovery in the git dialogs, for a
// branch that has DIVERGED from its upstream (Nam's repo
// `vault-portal-published`: `git pull` → "fatal: Not possible to fast-forward,
// aborting." because of `pull.ff=only`; `git push` → rejected non-fast-forward).
//
//  * SimpleGitPullDialog / RepoGitPullDialog: after a failed current-branch
//    pull on a diverged branch → hint line + "Pull (rebase)" button.
//  * SimpleGitPushDialog: after a rejected plain push while the remote is
//    ahead → hint line + "Pull (rebase) & push"; never in publishBranch mode.
//
// The dialogs call `startGit` / `runGit` directly (nothing to inject) → real
// git fixtures + `tester.runAsync`, and no `pumpAndSettle` (the
// LinearProgressIndicator animates forever). See the notes at the top of
// test/git_branch_dialog_push_button_test.dart. Every clone pins its own
// identity and pull/push config so the machine's global gitconfig cannot
// change the outcome.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/repo_git_pull_dialog.dart';
import 'package:odoo_auto_config/screens/other_projects/simple_git_pull_dialog.dart';
import 'package:odoo_auto_config/screens/other_projects/simple_git_push_dialog.dart';
import 'package:path/path.dart' as p;

/// Run git in [cwd]; fail the test when it exits non-zero.
Future<String> _git(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

Future<void> _configClone(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
  // Nam's exact setup: a plain pull refuses anything but a fast-forward.
  await _git(['config', 'pull.ff', 'only'], cwd);
  await _git(['config', 'pull.rebase', 'false'], cwd);
  await _git(['config', 'rebase.autostash', 'false'], cwd);
  await _git(['config', 'push.default', 'simple'], cwd);
  await _git(['config', 'push.autoSetupRemote', 'false'], cwd);
}

Future<void> _commitFile(
    String repo, String name, String content, String message) async {
  File(p.join(repo, name)).writeAsStringSync(content);
  await _git(['add', name], repo);
  await _git(['commit', '-m', message], repo);
}

const _pullRebaseLabel = 'Pull (rebase)';
const _pullRebasePushLabel = 'Pull (rebase) & push';
const _divergedHint = 'Local and remote have diverged';
const _pushBehindHint = "The remote has commits you don't have yet";
const _abortedLine = 'Rebase hit a conflict and was cancelled';
const _stashConflictLine = 'Rebased, but your uncommitted changes conflicted';
const _refusedLine = 'A rebase or merge is already in progress';

Finder _log(String text) => find.textContaining(text, findRichText: true);

void main() {
  late Directory tmp;
  late String remote;
  late String local;
  late String other;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pull_rebase_dialogs_');
    remote = p.join(tmp.path, 'remote.git');
    local = p.join(tmp.path, 'local');
    other = p.join(tmp.path, 'other');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Bare remote + `local` + `other` clones on `main`, one shared commit.
  Future<void> initFixture() async {
    Directory(remote).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remote], tmp.path);
    await _git(['clone', remote, local], tmp.path);
    await _configClone(local);
    await _commitFile(local, 'README.md', 'v1\n', 'initial');
    await _git(['push', '-u', 'origin', 'main'], local);
    await _git(['clone', remote, other], tmp.path);
    await _configClone(other);
  }

  /// `other` pushes [count] commits; `local` gets [localCommits] of its own.
  /// [conflict] makes both sides edit README.md instead.
  Future<void> diverge({
    int count = 1,
    int localCommits = 1,
    bool conflict = false,
  }) async {
    if (conflict) {
      await _commitFile(other, 'README.md', 'remote\n', 'remote edit');
      await _commitFile(local, 'README.md', 'local\n', 'local edit');
    } else {
      for (var i = 0; i < count; i++) {
        await _commitFile(other, 'remote-$i.txt', 'r$i\n', 'remote-$i');
      }
      for (var i = 0; i < localCommits; i++) {
        await _commitFile(local, 'local-$i.txt', 'l$i\n', 'local-$i');
      }
    }
    await _git(['push'], other);
  }

  /// Diverged (local 1 commit on l.txt, remote edits README.md) plus
  /// uncommitted WIP on README.md → the autostash conflicts on re-apply.
  Future<void> divergeWithOverlappingWip() async {
    await _commitFile(local, 'l.txt', 'l\n', 'local-0');
    await _commitFile(other, 'README.md', 'remote\n', 'remote edit');
    await _git(['push'], other);
    File(p.join(local, 'README.md')).writeAsStringSync('wip\n');
  }

  Widget wrap(Widget dialog) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: const TextScaler.linear(0.7),
          ),
          child: child!,
        ),
        home: Scaffold(body: dialog),
      );

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Inside runAsync: pump until the progress bar is gone, then a few more
  /// real-time pumps so late stdout/stderr lines (listeners are not awaited by
  /// the dialogs) land in the log.
  Future<void> waitIdle(WidgetTester tester, String what) async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        for (var j = 0; j < 4; j++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
        return;
      }
    }
    fail('$what did not finish within ~10s.');
  }

  Future<(int, int)> divergence(String cwd) async {
    final ahead =
        int.parse(await _git(['rev-list', '--count', '@{u}..HEAD'], cwd));
    final behind =
        int.parse(await _git(['rev-list', '--count', 'HEAD..@{u}'], cwd));
    return (ahead, behind);
  }

  // ── Pull dialogs (both share the same flow; run each case on both) ──

  final pullDialogs = <String, Widget Function(String path)>{
    'SimpleGitPullDialog': (path) =>
        SimpleGitPullDialog(projectName: 'fixture', projectPath: path),
    'RepoGitPullDialog': (path) =>
        RepoGitPullDialog(repoName: 'fixture', repoPath: path),
  };

  for (final entry in pullDialogs.entries) {
    final name = entry.key;
    final build = entry.value;

    group(name, () {
      testWidgets(
          'diverged + pull.ff=only → "Not possible to fast-forward", hint and '
          'button; tap → rebased, success line, button gone', (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          // Arrange: Nam's case — local 1 ahead, remote 5 ahead.
          await initFixture();
          await diverge(count: 5, localCommits: 1);

          // Act 1: the dialog runs a plain `git pull`.
          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');

          // Assert 1: the real git error, the hint and the button.
          expect(_log('Not possible to fast-forward'), findsOneWidget);
          expect(_log('Script failed with exit code'), findsOneWidget);
          expect(_log(_divergedHint), findsOneWidget);
          expect(find.text(_pullRebaseLabel), findsOneWidget);
          expect(_log('Done!'), findsNothing);

          // Act 2: Pull (rebase).
          await tester.tap(find.text(_pullRebaseLabel));
          await tester.pump();
          await waitIdle(tester, '$name pull --rebase');

          // Assert 2: success line, button gone, git really rebased.
          expect(_log('git pull --rebase --autostash'), findsOneWidget);
          expect(_log('Done!'), findsOneWidget);
          expect(find.text(_pullRebaseLabel), findsNothing);
          expect(await divergence(local), (1, 0));
          expect(await _git(['log', '-1', '--format=%s'], local), 'local-0');
        });
      });

      testWidgets('pull just succeeds (only behind) → no hint, no button',
          (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await diverge(count: 2, localCommits: 0);

          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');

          expect(_log('Done!'), findsOneWidget);
          expect(_log(_divergedHint), findsNothing);
          expect(find.text(_pullRebaseLabel), findsNothing);
          expect(await divergence(local), (0, 0));
        });
      });

      testWidgets('pull fails but branch is not diverged (no upstream) → '
          'no hint, no button', (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await _git(['checkout', '-b', 'orphan'], local);
          await _commitFile(local, 'x.txt', 'x\n', 'orphan commit');

          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');

          expect(_log('Script failed with exit code'), findsOneWidget);
          expect(_log(_divergedHint), findsNothing);
          expect(find.text(_pullRebaseLabel), findsNothing);
        });
      });

      testWidgets(
          'rebase fails WITHOUT a stopped rebase (remote gone before tap) → '
          'generic failure line, not the aborted line', (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await diverge(count: 1, localCommits: 1);
          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');
          expect(find.text(_pullRebaseLabel), findsOneWidget);
          await _git(
              ['remote', 'set-url', 'origin', p.join(tmp.path, 'gone.git')],
              local);

          await tester.tap(find.text(_pullRebaseLabel));
          await tester.pump();
          await waitIdle(tester, '$name pull --rebase');

          expect(_log('Script failed with exit code'), findsNWidgets(2));
          expect(_log(_abortedLine), findsNothing);
          expect(_log('Done!'), findsNothing);
        });
      });

      // Regression (review round 1): exit 0 with a conflicted autostash was
      // reported as "Done!".
      testWidgets('autostash conflict → warning line, NOT "Done!"',
          (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await divergeWithOverlappingWip();

          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');
          expect(find.text(_pullRebaseLabel), findsOneWidget);

          await tester.tap(find.text(_pullRebaseLabel));
          await tester.pump();
          await waitIdle(tester, '$name pull --rebase');

          expect(_log(_stashConflictLine), findsOneWidget);
          expect(_log('Done!'), findsNothing);
          expect(await _git(['ls-files', '-u'], local), isNotEmpty);
        });
      });

      // Regression (review round 1): a conflicting merge-pull leaves
      // MERGE_HEAD with HEAD still on the diverged branch; round-1 offered
      // the button in the middle of the merge.
      testWidgets('merge-pull conflict (pull.ff=false) → no hint, no button',
          (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await _git(['config', 'pull.ff', 'false'], local);
          await diverge(conflict: true);

          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');

          expect(_log('Script failed with exit code'), findsOneWidget);
          expect(File(p.join(local, '.git', 'MERGE_HEAD')).existsSync(),
              isTrue,
              reason: 'fixture: the dialog\'s own pull must stop mid-merge');
          expect(_log(_divergedHint), findsNothing);
          expect(find.text(_pullRebaseLabel), findsNothing);
        });
      });

      // Regression (review round 1): user starts their own rebase in a
      // terminal while the button is on screen; round-1 aborted it.
      testWidgets('user rebase started after the offer → tap → refused line, '
          'user rebase untouched', (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await diverge(conflict: true);
          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');
          expect(find.text(_pullRebaseLabel), findsOneWidget);
          final stop = await Process.run('git', ['rebase', 'origin/main'],
              workingDirectory: local);
          expect(stop.exitCode, isNot(0), reason: 'fixture: rebase stops');
          File(p.join(local, 'README.md')).writeAsStringSync('resolved\n');
          await _git(['add', 'README.md'], local);

          await tester.tap(find.text(_pullRebaseLabel));
          await tester.pump();
          await waitIdle(tester, '$name pull --rebase');

          expect(_log(_refusedLine), findsOneWidget);
          expect(_log(_abortedLine), findsNothing);
          expect(
              Directory(p.join(local, '.git', 'rebase-merge')).existsSync(),
              isTrue);
          expect(File(p.join(local, 'README.md')).readAsStringSync(),
              'resolved\n');
        });
      });

      testWidgets('diverged with a conflict → tap → aborted line, repo restored',
          (tester) async {
        bigView(tester);
        await tester.runAsync(() async {
          await initFixture();
          await diverge(conflict: true);
          final headBefore = await _git(['rev-parse', 'HEAD'], local);

          await tester.pumpWidget(wrap(build(local)));
          await waitIdle(tester, '$name pull');
          expect(find.text(_pullRebaseLabel), findsOneWidget);

          await tester.tap(find.text(_pullRebaseLabel));
          await tester.pump();
          await waitIdle(tester, '$name pull --rebase');

          expect(_log(_abortedLine), findsOneWidget);
          expect(_log('Done!'), findsNothing);
          expect(find.text(_pullRebaseLabel), findsNothing);
          expect(await _git(['rev-parse', 'HEAD'], local), headBefore);
          expect(File(p.join(local, 'README.md')).readAsStringSync(),
              'local\n');
          expect(
              Directory(p.join(local, '.git', 'rebase-merge')).existsSync(),
              isFalse);
        });
      });
    });
  }

  // ── Push dialog ──

  group('SimpleGitPushDialog', () {
    Future<void> mountPush(WidgetTester tester, {String? publishBranch}) async {
      await tester.pumpWidget(wrap(SimpleGitPushDialog(
        projectName: 'fixture',
        projectPath: local,
        publishBranch: publishBranch,
      )));
      await waitIdle(tester, 'push');
    }

    testWidgets(
        'rejected (another clone pushed, stale tracking ref) → hint + button; '
        'tap → rebase then push again → "Pushed!", remote has both commits',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        // Arrange: `local` has NOT fetched `other`'s push.
        await initFixture();
        await diverge(count: 1, localCommits: 1);

        await mountPush(tester);

        expect(_log('Push failed with exit code'), findsOneWidget);
        expect(_log(_pushBehindHint), findsOneWidget);
        expect(find.text(_pullRebasePushLabel), findsOneWidget);
        expect(_log('Pushed!'), findsNothing);

        await tester.tap(find.text(_pullRebasePushLabel));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase + push');

        expect(_log('Done!'), findsOneWidget);
        expect(_log('Pushed!'), findsOneWidget);
        expect(find.text(_pullRebasePushLabel), findsNothing);
        final remoteLog =
            await _git(['log', '--format=%s', 'main'], remote);
        expect(remoteLog.split('\n'), ['local-0', 'remote-0', 'initial']);
        expect(await divergence(local), (0, 0));
      });
    });

    // Regression (review round 1): stashConflict must still push — the
    // commits rebased fine, only the WIP conflicted.
    testWidgets('autostash conflict → warning line AND still pushes',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        await initFixture();
        await divergeWithOverlappingWip();

        await mountPush(tester);
        expect(find.text(_pullRebasePushLabel), findsOneWidget);

        await tester.tap(find.text(_pullRebasePushLabel));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase + push');

        expect(_log(_stashConflictLine), findsOneWidget);
        expect(_log('Done!'), findsNothing);
        expect(_log('Pushed!'), findsOneWidget);
        final remoteLog = await _git(['log', '--format=%s', 'main'], remote);
        expect(remoteLog.split('\n'), ['local-0', 'remote edit', 'initial']);
      });
    });

    testWidgets('rejected with a conflict → tap → aborted line, no second push',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        await initFixture();
        await diverge(conflict: true);
        final remoteBefore = await _git(['rev-parse', 'main'], remote);

        await mountPush(tester);
        expect(find.text(_pullRebasePushLabel), findsOneWidget);

        await tester.tap(find.text(_pullRebasePushLabel));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase + push');

        expect(_log(_abortedLine), findsOneWidget);
        expect(_log('Pushed!'), findsNothing);
        expect(_log('Push failed with exit code'), findsOneWidget,
            reason: 'only the first, rejected push may have run');
        expect(await _git(['rev-parse', 'main'], remote), remoteBefore);
      });
    });

    testWidgets(
        'rebase fails WITHOUT a stopped rebase (remote gone before tap) → '
        'failure line, no second push', (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        await initFixture();
        await diverge(count: 1, localCommits: 1);
        await mountPush(tester);
        expect(find.text(_pullRebasePushLabel), findsOneWidget);
        // The remote disappears between the offer and the tap.
        await _git(
            ['remote', 'set-url', 'origin', p.join(tmp.path, 'gone.git')],
            local);

        await tester.tap(find.text(_pullRebasePushLabel));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase + push');

        expect(_log('Script failed with exit code'), findsOneWidget);
        expect(_log(_abortedLine), findsNothing);
        expect(_log('Push failed with exit code'), findsOneWidget,
            reason: 'a failed (not aborted) rebase must not push again');
        expect(_log('Pushed!'), findsNothing);
      });
    });

    testWidgets(
        'publishBranch mode → no button even when the rejected branch is '
        'diverged', (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        // Contrived on purpose: `main` HAS an upstream and IS behind, so the
        // only thing keeping the button away is the publishBranch guard.
        await initFixture();
        await diverge(count: 1, localCommits: 1);

        await mountPush(tester, publishBranch: 'main');

        expect(_log('Push failed with exit code'), findsOneWidget);
        expect(_log(_pushBehindHint), findsNothing);
        expect(find.text(_pullRebasePushLabel), findsNothing);
      });
    });

    testWidgets('plain push fails with no upstream → no button',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        await initFixture();
        await _git(['checkout', '-b', 'orphan'], local);
        await _commitFile(local, 'x.txt', 'x\n', 'orphan commit');

        await mountPush(tester);

        expect(_log('Push failed with exit code'), findsOneWidget);
        expect(find.text(_pullRebasePushLabel), findsNothing);
      });
    });

    testWidgets('push succeeds → no button', (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        await initFixture();
        await _commitFile(local, 'x.txt', 'x\n', 'ahead only');

        await mountPush(tester);

        expect(_log('Pushed!'), findsOneWidget);
        expect(find.text(_pullRebasePushLabel), findsNothing);
      });
    });
  });
}
