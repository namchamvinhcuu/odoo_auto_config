// Widget tests for the multi-repo "Pull (rebase) (N)" recovery:
//  * GitActionDialog (Workspace multi-repo Pull/Push, also behind the single
//    Workspace tile buttons) — collects repos whose pull/push failed because
//    they diverged, then offers one button for all of them.
//  * SelectivePullLogDialog (Odoo projects Selective Pull, Other Projects
//    "Pull all") — same for pull.
//
// Real git fixtures + `tester.runAsync`, no pumpAndSettle (see the notes at the
// top of test/git_branch_dialog_push_button_test.dart). Every clone pins its own
// identity and pull/push config.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/screens/odoo_projects/selective_pull_log_dialog.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/git_action_dialog.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/repo_info.dart';
import 'package:path/path.dart' as p;

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

/// One bare remote + `local` + `other` clone under `<root>/<name>/`.
class _Repo {
  final String name;
  final String dir;
  _Repo(String root, this.name) : dir = p.join(root, name);
  String get remote => p.join(dir, 'remote.git');
  String get local => p.join(dir, 'local');
  String get other => p.join(dir, 'other');

  Future<void> init() async {
    Directory(remote).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remote], dir);
    await _git(['clone', remote, local], dir);
    await _configClone(local);
    await _commitFile(local, 'README.md', 'v1\n', 'initial');
    await _git(['push', '-u', 'origin', 'main'], local);
    await _git(['clone', remote, other], dir);
    await _configClone(other);
  }

  Future<void> remoteCommit(String msg, {bool push = true}) async {
    await _commitFile(other, '$msg.txt', '$msg\n', msg);
    if (push) await _git(['push'], other);
  }

  Future<void> localCommit(String msg) =>
      _commitFile(local, '$msg.txt', '$msg\n', msg);

  Future<String> head() => _git(['rev-parse', 'HEAD'], local);

  Future<(int, int)> divergence() async {
    final a = int.parse(await _git(['rev-list', '--count', '@{u}..HEAD'], local));
    final b = int.parse(await _git(['rev-list', '--count', 'HEAD..@{u}'], local));
    return (a, b);
  }
}

const _pullRebase = 'Pull (rebase)';
const _pullRebasePush = 'Pull (rebase) & push';
const _divergedHint = 'Local and remote have diverged';
const _pushBehindHint = "The remote has commits you don't have yet";

Finder _log(String text) => find.textContaining(text, findRichText: true);

/// The rebase button (its label text also appears inside the hint lines).
final _rebaseButton = find.byIcon(Icons.call_merge);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pull_rebase_multi_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

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
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> waitIdle(WidgetTester tester, String what) async {
    for (var i = 0; i < 300; i++) {
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
    fail('$what did not finish within ~15s.');
  }

  /// diverged (1 local, 1 remote) · ok (only behind) · ahead (only ahead).
  Future<({_Repo diverged, _Repo ok, _Repo ahead})> threeRepos() async {
    final diverged = _Repo(tmp.path, 'diverged');
    final ok = _Repo(tmp.path, 'ok');
    final ahead = _Repo(tmp.path, 'ahead');
    for (final r in [diverged, ok, ahead]) {
      await r.init();
    }
    await diverged.localCommit('local-0');
    await diverged.remoteCommit('remote-0');
    await ok.remoteCommit('remote-ok');
    await ahead.localCommit('ahead-0');
    return (diverged: diverged, ok: ok, ahead: ahead);
  }

  group('GitActionDialog', () {
    testWidgets(
        'pull: 3 repos (diverged / only behind / only ahead) → one '
        '"Pull (rebase) (1)"; tap rebases only the diverged one, onDone again',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        final r = await threeRepos();
        var done = 0;
        await tester.pumpWidget(wrap(GitActionDialog(
          title: 'Pull',
          action: 'pull',
          repos: [
            RepoInfo(name: 'diverged', path: r.diverged.local),
            RepoInfo(name: 'ok', path: r.ok.local),
            RepoInfo(name: 'ahead', path: r.ahead.local),
          ],
          onDone: () => done++,
        )));
        await waitIdle(tester, 'batch pull');

        expect(done, 1);
        expect(_log('diverged: failed (exit'), findsOneWidget);
        expect(_log('diverged: $_divergedHint'), findsOneWidget);
        expect(_log(_divergedHint), findsOneWidget,
            reason: 'only the diverged repo gets a hint');
        expect(find.text('$_pullRebase (1)'), findsOneWidget);
        final okHead = await r.ok.head();
        final aheadHead = await r.ahead.head();

        await tester.tap(find.text('$_pullRebase (1)'));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase candidates');

        expect(done, 2, reason: 'onDone must reload after the rebase too');
        expect(_rebaseButton, findsNothing);
        expect(_log('git pull --rebase --autostash (diverged)'), findsOneWidget);
        expect(_log('--rebase --autostash (ok)'), findsNothing);
        expect(_log('--rebase --autostash (ahead)'), findsNothing);
        expect(_log('diverged: Done!'), findsOneWidget);
        expect(_log('Pushing'), findsNothing,
            reason: 'the pull action must never push');
        expect(await r.diverged.divergence(), (1, 0));
        expect(await r.ok.head(), okHead);
        expect(await r.ahead.head(), aheadHead);
      });
    });

    testWidgets(
        'push: diverged repo (stale tracking ref) + ok repo → '
        '"Pull (rebase) & push (1)"; tap → rebase then push, remote has it',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        final diverged = _Repo(tmp.path, 'diverged');
        final ok = _Repo(tmp.path, 'ok');
        await diverged.init();
        await ok.init();
        await diverged.localCommit('local-0');
        await diverged.remoteCommit('remote-0');
        await ok.localCommit('ok-0');
        var done = 0;
        await tester.pumpWidget(wrap(GitActionDialog(
          title: 'Push',
          action: 'push',
          repos: [
            RepoInfo(name: 'diverged', path: diverged.local),
            RepoInfo(name: 'ok', path: ok.local),
          ],
          onDone: () => done++,
        )));
        await waitIdle(tester, 'batch push');

        expect(done, 1);
        expect(_log('diverged: push failed'), findsOneWidget);
        expect(_log('diverged: $_pushBehindHint'), findsOneWidget);
        expect(_log('ok: pushed'), findsOneWidget);
        expect(find.text('$_pullRebasePush (1)'), findsOneWidget);

        await tester.tap(find.text('$_pullRebasePush (1)'));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase + push');

        expect(done, 2);
        expect(_log('diverged: Done!'), findsOneWidget);
        expect(_log('diverged: pushed'), findsOneWidget);
        expect(_rebaseButton, findsNothing);
        final remoteLog =
            await _git(['log', '--format=%s', 'main'], diverged.remote);
        expect(remoteLog.split('\n'), ['local-0', 'remote-0', 'initial']);
      });
    });

    testWidgets(
        'push: the push after the rebase is rejected again → no new offer '
        '(no loop)', (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        final repo = _Repo(tmp.path, 'diverged');
        await repo.init();
        await repo.localCommit('local-0');
        await repo.remoteCommit('remote-0');
        // Prepared now, pushed by the hook below right before failing the push.
        await repo.remoteCommit('remote-1', push: false);
        await tester.pumpWidget(wrap(GitActionDialog(
          title: 'Push',
          action: 'push',
          repos: [RepoInfo(name: 'diverged', path: repo.local)],
          onDone: () {},
        )));
        await waitIdle(tester, 'batch push');
        expect(find.text('$_pullRebasePush (1)'), findsOneWidget);

        // pre-push hook: the remote moves on again, then this push fails →
        // the branch is diverged again, an offer WOULD be valid.
        final hook = File(p.join(repo.local, '.git', 'hooks', 'pre-push'))
          ..writeAsStringSync('#!/bin/sh\n'
              'env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE '
              'git -C "${repo.other}" push -q\n'
              'exit 1\n');
        await Process.run('chmod', ['+x', hook.path]);

        await tester.tap(find.text('$_pullRebasePush (1)'));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase + push');

        expect(_log('diverged: Done!'), findsOneWidget);
        expect(_log('diverged: push failed'), findsNWidgets(2));
        expect(_log(_pushBehindHint), findsOneWidget,
            reason: 'only the first rejection may offer');
        expect(_rebaseButton, findsNothing);
        expect(
            await _git(['log', '-1', '--format=%s', 'main'], repo.remote),
            'remote-1',
            reason: 'fixture: the hook really moved the remote');
      });
    });
  });

  group('SelectivePullLogDialog', () {
    testWidgets(
        '3 repos (diverged / only behind / only ahead) → "Pull (rebase) (1)"; '
        'tap rebases only the diverged one', (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        final r = await threeRepos();
        await tester.pumpWidget(wrap(SelectivePullLogDialog(
          title: 'Pull all',
          repos: [
            (name: 'diverged', path: r.diverged.local),
            (name: 'ok', path: r.ok.local),
            (name: 'ahead', path: r.ahead.local),
          ],
        )));
        await waitIdle(tester, 'batch pull');

        expect(_log('diverged failed (exit'), findsOneWidget);
        expect(_log('diverged: $_divergedHint'), findsOneWidget);
        expect(_log(_divergedHint), findsOneWidget);
        expect(_log('ok done'), findsOneWidget);
        expect(_log('ahead done'), findsOneWidget);
        expect(find.text('$_pullRebase (1)'), findsOneWidget);
        final okHead = await r.ok.head();
        final aheadHead = await r.ahead.head();

        await tester.tap(find.text('$_pullRebase (1)'));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase candidates');

        expect(_rebaseButton, findsNothing);
        expect(_log('git pull --rebase --autostash (diverged)'), findsOneWidget);
        expect(_log('--rebase --autostash (ok)'), findsNothing);
        expect(_log('diverged: Done!'), findsOneWidget);
        expect(await r.diverged.divergence(), (1, 0));
        expect(await r.ok.head(), okHead);
        expect(await r.ahead.head(), aheadHead);
      });
    });

    testWidgets('2 diverged repos → "Pull (rebase) (2)", tap rebases both',
        (tester) async {
      bigView(tester);
      await tester.runAsync(() async {
        final a = _Repo(tmp.path, 'a');
        final b = _Repo(tmp.path, 'b');
        for (final r in [a, b]) {
          await r.init();
          await r.localCommit('local-0');
          await r.remoteCommit('remote-0');
        }
        await tester.pumpWidget(wrap(SelectivePullLogDialog(
          title: 'Pull all',
          repos: [(name: 'a', path: a.local), (name: 'b', path: b.local)],
        )));
        await waitIdle(tester, 'batch pull');
        expect(find.text('$_pullRebase (2)'), findsOneWidget);

        await tester.tap(find.text('$_pullRebase (2)'));
        await tester.pump();
        await waitIdle(tester, 'pull --rebase candidates');

        expect(_log('a: Done!'), findsOneWidget);
        expect(_log('b: Done!'), findsOneWidget);
        expect(await a.divergence(), (1, 0));
        expect(await b.divergence(), (1, 0));
      });
    });
  });
}
