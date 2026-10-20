// Tests for `GitPullRebaseService` — recovery for a branch that has DIVERGED
// from its upstream (local commits + new remote commits). Origin: Nam's repo
// `vault-portal-published`, local 1 ahead / remote 5 ahead, with
// `pull.ff=only` → `git pull` fails "Not possible to fast-forward" and
// `git push` is rejected non-fast-forward.
//
// Real git fixtures (bare remote + 2 clones) in a temp dir; every clone pins
// its own identity and pull config so the machine's global gitconfig
// (pull.rebase / pull.ff / rebase.autostash) cannot change the outcome.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_pull_rebase_service.dart';
import 'package:path/path.dart' as p;

Future<ProcessResult> _gitRaw(List<String> args, String cwd) =>
    Process.run('git', args, workingDirectory: cwd);

/// Run git in [cwd]; fail the test when it exits non-zero.
Future<String> _git(List<String> args, String cwd) async {
  final r = await _gitRaw(args, cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

Future<void> _configClone(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
  // Nam's setup: plain pull refuses anything but a fast-forward.
  await _git(['config', 'pull.ff', 'only'], cwd);
  await _git(['config', 'pull.rebase', 'false'], cwd);
  await _git(['config', 'rebase.autostash', 'false'], cwd);
}

Future<void> _commitFile(String repo, String name, String content,
    String message) async {
  File(p.join(repo, name)).writeAsStringSync(content);
  await _git(['add', name], repo);
  await _git(['commit', '-m', message], repo);
}

/// Bare remote + `local` + `other` clones, both on `main` tracking origin/main
/// with one shared commit (README.md = "v1").
class _Fixture {
  final String root;
  _Fixture(this.root);
  String get remote => p.join(root, 'remote.git');
  String get local => p.join(root, 'local');
  String get other => p.join(root, 'other');

  Future<void> init() async {
    Directory(remote).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remote], root);
    await _git(['clone', remote, local], root);
    await _configClone(local);
    await _commitFile(local, 'README.md', 'v1\n', 'initial');
    await _git(['push', '-u', 'origin', 'main'], local);
    await _git(['clone', remote, other], root);
    await _configClone(other);
  }

  /// [count] commits pushed from `other`, then fetched into `local` unless
  /// [fetchIntoLocal] is false (stale remote-tracking ref).
  Future<void> remoteAhead(int count, {bool fetchIntoLocal = true}) async {
    for (var i = 0; i < count; i++) {
      await _commitFile(other, 'remote-$i.txt', 'r$i\n', 'remote-$i');
    }
    await _git(['push'], other);
    if (fetchIntoLocal) await _git(['fetch'], local);
  }

  Future<void> localAhead(int count) async {
    for (var i = 0; i < count; i++) {
      await _commitFile(local, 'local-$i.txt', 'l$i\n', 'local-$i');
    }
  }

  Future<(int ahead, int behind)> divergence() async {
    final ahead =
        int.parse(await _git(['rev-list', '--count', '@{u}..HEAD'], local));
    final behind =
        int.parse(await _git(['rev-list', '--count', 'HEAD..@{u}'], local));
    return (ahead, behind);
  }
}

/// `local` 1 ahead (README "local") + remote 1 ahead (README "remote", fetched),
/// then `git am` of a conflicting patch stops with `rebase-apply` while HEAD
/// stays on `main`.
Future<void> _stoppedAmOnDivergedBranch(_Fixture fx, String root) async {
  await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
  await _git(['push'], fx.other);
  final patch = await _git(['format-patch', '-1', '--stdout'], fx.other);
  final patchFile = p.join(root, 'conflict.patch');
  File(patchFile).writeAsStringSync('$patch\n');
  await _commitFile(fx.local, 'README.md', 'local\n', 'local edit');
  await _git(['fetch'], fx.local);
  final r = await _gitRaw(['am', patchFile], fx.local);
  expect(r.exitCode, isNot(0), reason: 'fixture: `git am` must stop');
  expect(await _git(['symbolic-ref', '--short', 'HEAD'], fx.local), 'main');
}

void main() {
  late Directory tmp;
  late _Fixture fx;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('git_pull_rebase_');
    fx = _Fixture(tmp.path);
    await fx.init();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('canOfferPullRebase', () {
    test('diverged (1 ahead, 5 behind — Nam\'s case) → true', () async {
      await fx.localAhead(1);
      await fx.remoteAhead(5);

      final offer = await GitPullRebaseService.canOfferPullRebase(fx.local);

      expect(offer, isTrue);
    });

    test('only behind → false (plain pull fast-forwards)', () async {
      await fx.remoteAhead(2);

      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });

    test('only ahead → false (plain push works)', () async {
      await fx.localAhead(2);

      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });

    test('no upstream → false', () async {
      await _git(['checkout', '-b', 'orphan'], fx.local);
      await fx.localAhead(1);

      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });

    test('diverged but a rebase is already stopped → false', () async {
      // Arrange: conflicting change on both sides, then a manual rebase that
      // stops on the conflict.
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      await _git(['fetch'], fx.local);
      await _commitFile(fx.local, 'README.md', 'local\n', 'local edit');
      final r = await _gitRaw(['rebase', 'origin/main'], fx.local);
      expect(r.exitCode, isNot(0), reason: 'fixture must stop on conflict');

      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isTrue);
      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });

    test('diverged, still ON the branch, but a `git am` is stopped '
        '(rebase-apply) → false', () async {
      // A stopped `git rebase` detaches HEAD, so `@{upstream}` already fails
      // there; `git am` keeps HEAD on the branch — the case where only the
      // isRebaseInProgress guard keeps the button away.
      await _stoppedAmOnDivergedBranch(fx, tmp.path);
      expect(await fx.divergence(), (1, 1));

      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isTrue);
      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });
  });

  group('isRebaseInProgress', () {
    test('clean repo → false', () async {
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isFalse);
    });

    test('linked worktree (absolute --git-path) with a stopped rebase → true',
        () async {
      // `rev-parse --git-path` answers an ABSOLUTE path in a linked worktree;
      // the relative case is covered by the test above (main checkout).
      final wt = p.join(tmp.path, 'wt');
      await _git(['worktree', 'add', '-b', 'wtb', wt, 'main'], fx.local);
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      await _git(['fetch'], wt);
      await _commitFile(wt, 'README.md', 'wt\n', 'wt edit');
      final r = await _gitRaw(['rebase', 'origin/main'], wt);
      expect(r.exitCode, isNot(0), reason: 'fixture must stop on conflict');

      expect(await GitPullRebaseService.isRebaseInProgress(wt), isTrue);
      // The main checkout is not rebasing.
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isFalse);
    });
  });

  group('pullRebase', () {
    test('diverged → success, local commit on top of remote (ahead 1 behind 0)',
        () async {
      await fx.localAhead(1);
      await fx.remoteAhead(5);
      final lines = <String>[];

      final result = await GitPullRebaseService.pullRebase(
        fx.local,
        onOutput: lines.add,
      );

      expect(result.outcome, PullRebaseOutcome.success,
          reason: lines.join('\n'));
      expect(result.exitCode, 0);
      expect(await fx.divergence(), (1, 0));
      expect(await _git(['log', '-1', '--format=%s'], fx.local), 'local-0');
      expect(File(p.join(fx.local, 'remote-4.txt')).existsSync(), isTrue);
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isFalse);
    });

    test('dirty working tree is preserved through autostash', () async {
      await fx.localAhead(1);
      await fx.remoteAhead(1);
      File(p.join(fx.local, 'README.md')).writeAsStringSync('v1\nwip\n');

      final result =
          await GitPullRebaseService.pullRebase(fx.local, onOutput: (_) {});

      expect(result.outcome, PullRebaseOutcome.success);
      expect(await fx.divergence(), (1, 0));
      expect(File(p.join(fx.local, 'README.md')).readAsStringSync(),
          'v1\nwip\n');
      expect(await _git(['status', '--porcelain'], fx.local), 'M README.md');
      expect(await _git(['stash', 'list'], fx.local), isEmpty,
          reason: 'autostash must be popped, not left in the stash list');
    });

    test('conflict → aborted, HEAD + working tree + WIP restored, '
        'no rebase in progress', () async {
      // Arrange: both sides edit README.md; plus uncommitted WIP elsewhere.
      await _commitFile(fx.local, 'notes.txt', 'n1\n', 'notes');
      await _commitFile(fx.local, 'README.md', 'local\n', 'local edit');
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      final headBefore = await _git(['rev-parse', 'HEAD'], fx.local);
      File(p.join(fx.local, 'notes.txt')).writeAsStringSync('n1\nwip\n');
      final lines = <String>[];

      final result = await GitPullRebaseService.pullRebase(
        fx.local,
        onOutput: lines.add,
      );

      expect(result.outcome, PullRebaseOutcome.aborted,
          reason: lines.join('\n'));
      expect(result.exitCode, isNot(0));
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isFalse);
      expect(await _git(['rev-parse', 'HEAD'], fx.local), headBefore);
      expect(await _git(['symbolic-ref', '--short', 'HEAD'], fx.local), 'main',
          reason: 'must be back on the branch, not a detached HEAD');
      expect(File(p.join(fx.local, 'README.md')).readAsStringSync(), 'local\n');
      expect(File(p.join(fx.local, 'notes.txt')).readAsStringSync(),
          'n1\nwip\n');
      expect(await _git(['status', '--porcelain'], fx.local), 'M notes.txt');
      expect(lines.join('\n'), contains('CONFLICT'),
          reason: 'git output must be streamed to onOutput');
    });

    test('fails without leaving a rebase (no upstream) → not aborted',
        () async {
      await _git(['checkout', '-b', 'orphan'], fx.local);
      await fx.localAhead(1);

      final result =
          await GitPullRebaseService.pullRebase(fx.local, onOutput: (_) {});

      expect(result.outcome, PullRebaseOutcome.failed);
      expect(result.exitCode, isNot(0));
    });

    // Regression (review round 1): the button can sit on screen while the user
    // starts their own rebase in a terminal; round-1 code ran the pull, saw a
    // stopped rebase and ran `rebase --abort` — throwing away the user's
    // staged resolution.
    test('user\'s own rebase stopped with a staged resolution → refused, '
        'resolution untouched, nothing run', () async {
      await _commitFile(fx.local, 'README.md', 'local\n', 'local edit');
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      await _git(['fetch'], fx.local);
      final stop = await _gitRaw(['rebase', 'origin/main'], fx.local);
      expect(stop.exitCode, isNot(0), reason: 'fixture must stop on conflict');
      File(p.join(fx.local, 'README.md')).writeAsStringSync('resolved\n');
      await _git(['add', 'README.md'], fx.local);
      final stagedBefore = await _git(['rev-parse', ':README.md'], fx.local);
      final lines = <String>[];

      final result =
          await GitPullRebaseService.pullRebase(fx.local, onOutput: lines.add);

      expect(result.outcome, PullRebaseOutcome.refused);
      expect(lines, isEmpty, reason: 'no git command may have run');
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isTrue,
          reason: 'the user\'s rebase must still be there');
      expect(await _git(['rev-parse', ':README.md'], fx.local), stagedBefore);
      expect(File(p.join(fx.local, 'README.md')).readAsStringSync(),
          'resolved\n');
    });

    // Regression (review round 1): an autostash that conflicts on re-apply
    // still exits 0; round-1 code reported plain success ("Done!").
    test('autostash conflict (WIP overlaps a remote change) → stashConflict, '
        'commits rebased, WIP kept in the stash, files unmerged', () async {
      await fx.localAhead(1);
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      File(p.join(fx.local, 'README.md')).writeAsStringSync('wip\n');

      final result =
          await GitPullRebaseService.pullRebase(fx.local, onOutput: (_) {});

      expect(result.outcome, PullRebaseOutcome.stashConflict);
      expect(result.exitCode, 0);
      expect(await fx.divergence(), (1, 0),
          reason: 'the commits themselves rebased fine');
      expect(await _git(['ls-files', '-u'], fx.local), isNotEmpty);
      expect(await _git(['stash', 'list'], fx.local), contains('autostash'));
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isFalse);
    });

    test('rebase stops and `rebase --abort` fails (index.lock) → '
        'stuckInRebase, rebase still in progress', () async {
      await _commitFile(fx.local, 'README.md', 'local\n', 'local edit');
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      final lock = File(p.join(fx.local, '.git', 'index.lock'));
      final applyFailed = RegExp('could not apply', caseSensitive: false);

      // Create the lock once the rebase has stopped (git prints "could not
      // apply" after writing the conflicted index), before the abort runs.
      final result = await GitPullRebaseService.pullRebase(
        fx.local,
        onOutput: (line) {
          if (applyFailed.hasMatch(line) && !lock.existsSync()) {
            lock.createSync();
          }
        },
      );

      expect(lock.existsSync(), isTrue, reason: 'fixture: lock was created');
      expect(result.outcome, PullRebaseOutcome.stuckInRebase);
      expect(result.exitCode, isNot(0));
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isTrue);
    });

    // Regression (review round 1): round-1 used the strict utf8 decoder; a
    // non-UTF-8 byte in git's output threw out of pullRebase BEFORE the abort,
    // leaving the repo mid-rebase.
    test('non-UTF-8 git output (latin1 commit subject) → no throw, aborted, '
        'no rebase left', () async {
      await _git(['config', 'i18n.logOutputEncoding', 'ISO-8859-1'], fx.local);
      File(p.join(fx.local, 'README.md')).writeAsStringSync('local\n');
      await _git(['add', 'README.md'], fx.local);
      final msg = File(p.join(tmp.path, 'latin1-msg.txt'))
        ..writeAsBytesSync([...'caf'.codeUnits, 0xE9, ...' local\n'.codeUnits]);
      // -q: the fixture's own Process.run decodes strictly too.
      await _git(['commit', '-q', '-F', msg.path], fx.local);
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      final lines = <String>[];

      final result =
          await GitPullRebaseService.pullRebase(fx.local, onOutput: lines.add);

      expect(result.outcome, PullRebaseOutcome.aborted);
      expect(await GitPullRebaseService.isRebaseInProgress(fx.local), isFalse);
      expect(lines.any((l) => l.contains('�')), isTrue,
          reason: 'fixture: the malformed byte must reach the decoder');
    });
  });

  // Regression (review round 1): a conflicting merge-pull (`pull.ff=false`)
  // keeps HEAD on the branch and the branch still diverged; round-1 code
  // offered the button in the middle of the user's merge.
  group('merge in progress / unmerged files', () {
    Future<void> conflictingMergePull() async {
      await _git(['config', 'pull.ff', 'false'], fx.local);
      await _commitFile(fx.local, 'README.md', 'local\n', 'local edit');
      await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
      await _git(['push'], fx.other);
      final r = await _gitRaw(['pull'], fx.local);
      expect(r.exitCode, isNot(0), reason: 'fixture: merge must conflict');
      expect(await fx.divergence(), (1, 1));
    }

    String mergeHead() => p.join(fx.local, '.git', 'MERGE_HEAD');

    test('MERGE_HEAD + unmerged → no offer (both), pullRebase refused, '
        'merge left as is', () async {
      await conflictingMergePull();

      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
      expect(
          await GitPullRebaseService.canOfferPullRebaseAfterPushRejected(
              fx.local),
          isFalse);
      final result =
          await GitPullRebaseService.pullRebase(fx.local, onOutput: (_) {});
      expect(result.outcome, PullRebaseOutcome.refused);
      expect(File(mergeHead()).existsSync(), isTrue);
      expect(await _git(['ls-files', '-u'], fx.local), isNotEmpty);
    });

    test('MERGE_HEAD only (conflict resolved and staged) → no offer',
        () async {
      await conflictingMergePull();
      File(p.join(fx.local, 'README.md')).writeAsStringSync('resolved\n');
      await _git(['add', 'README.md'], fx.local);
      expect(await _git(['ls-files', '-u'], fx.local), isEmpty);

      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });

    test('unmerged files only (no MERGE_HEAD) → no offer', () async {
      await conflictingMergePull();
      await _git(['update-ref', '-d', 'MERGE_HEAD'], fx.local);
      expect(File(mergeHead()).existsSync(), isFalse);

      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);
    });

    // Regression (review round 2): plain `ls-files -u` lists only the cwd, so
    // with workingDir = a subdir the conflicted README.md at the top level was
    // invisible and the repo looked idle.
    test('workingDir is a SUBDIR, unmerged file at the top level → no offer, '
        'pullRebase refused', () async {
      await conflictingMergePull();
      await _git(['update-ref', '-d', 'MERGE_HEAD'], fx.local);
      final sub = Directory(p.join(fx.local, 'sub'))..createSync();
      expect(await fx.divergence(), (1, 1));

      expect(await GitPullRebaseService.canOfferPullRebase(sub.path), isFalse);
      final lines = <String>[];
      final result =
          await GitPullRebaseService.pullRebase(sub.path, onOutput: lines.add);
      expect(result.outcome, PullRebaseOutcome.refused);
      expect(lines, isEmpty, reason: 'no git command may have run');
      expect(await _git(['ls-files', '-u'], fx.local), isNotEmpty,
          reason: 'the conflict must be left as is');
    });
  });

  test('stashConflict is detected when workingDir is a SUBDIR', () async {
    // Regression (review round 2): same cwd-only `ls-files -u` — the
    // conflicted autostash on top-level README.md read as plain success.
    await _commitFile(fx.local, 'sub-keep.txt', 'k\n', 'local-0');
    final sub = Directory(p.join(fx.local, 'sub'))..createSync();
    File(p.join(sub.path, 'keep.txt')).writeAsStringSync('k\n');
    await _git(['add', 'sub/keep.txt'], fx.local);
    await _git(['commit', '-m', 'sub dir'], fx.local);
    await _commitFile(fx.other, 'README.md', 'remote\n', 'remote edit');
    await _git(['push'], fx.other);
    File(p.join(fx.local, 'README.md')).writeAsStringSync('wip\n');

    final result =
        await GitPullRebaseService.pullRebase(sub.path, onOutput: (_) {});

    expect(result.outcome, PullRebaseOutcome.stashConflict);
    expect(await fx.divergence(), (2, 0));
    expect(await _git(['ls-files', '-u', '--', 'README.md'], fx.local),
        isNotEmpty);
  });

  group('canOfferPullRebaseAfterPushRejected', () {
    test('another clone pushed (stale tracking ref) → fetches → true',
        () async {
      await fx.localAhead(1);
      await fx.remoteAhead(1, fetchIntoLocal: false);
      // Without a fetch the tracking ref says "only ahead".
      expect(await GitPullRebaseService.canOfferPullRebase(fx.local), isFalse);

      final offer =
          await GitPullRebaseService.canOfferPullRebaseAfterPushRejected(
              fx.local);

      expect(offer, isTrue);
      expect(await fx.divergence(), (1, 1));
    });

    test('remote not ahead → false', () async {
      await fx.localAhead(1);

      expect(
          await GitPullRebaseService.canOfferPullRebaseAfterPushRejected(
              fx.local),
          isFalse);
    });

    test('no upstream → false', () async {
      await _git(['checkout', '-b', 'orphan'], fx.local);
      await fx.localAhead(1);

      expect(
          await GitPullRebaseService.canOfferPullRebaseAfterPushRejected(
              fx.local),
          isFalse);
    });

    test('remote ahead but a `git am` is stopped on the branch → false',
        () async {
      await _stoppedAmOnDivergedBranch(fx, tmp.path);

      expect(
          await GitPullRebaseService.canOfferPullRebaseAfterPushRejected(
              fx.local),
          isFalse);
    });

    test('fetch fails (remote gone) → false even though tracking ref is behind',
        () async {
      await fx.localAhead(1);
      await fx.remoteAhead(1); // tracking ref already says behind 1
      await _git(['remote', 'set-url', 'origin', p.join(tmp.path, 'nope.git')],
          fx.local);

      expect(
          await GitPullRebaseService.canOfferPullRebaseAfterPushRejected(
              fx.local),
          isFalse);
    });
  });
}
