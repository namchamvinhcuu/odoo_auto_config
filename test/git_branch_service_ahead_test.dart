// Regression test cho bug `push-btn-ahead-detect`:
//
// Repo đã `git commit` local nhưng CHƯA `git push` thì app không báo gì:
// `GitBranchService.loadBranches()` chỉ tính `changedFiles` (= 0 khi tree
// clean) + `behindRemote` (= 0 khi remote không có gì mới) và KHÔNG hề chạy
// `git rev-list --count @{upstream}..HEAD` → dialog Git Branches hiện nút
// Commit *disabled* và không badge nào ⇒ commit local bị bỏ quên.
//
// Fix: `BranchesResult` thêm `aheadRemote` + `hasUpstream`; thêm
// `GitBranchService.pushCurrentBranch()` để dialog có đường push.
//
// Test dùng git fixture THẬT (bare remote + local clone) — chạm Process.run
// thật, cần `git` trong PATH. Tái dùng pattern fixture của
// test/other_projects_behind_count_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';
import 'package:path/path.dart' as p;

/// Chạy 1 lệnh git trong [cwd], fail test nếu exitCode != 0.
Future<void> _git(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
}

/// Đảm bảo commit không bị chặn bởi global hooks / thiếu user.* config.
///
/// `push.autoSetupRemote false` được pin để test deterministic trên mọi máy:
/// với `autoSetupRemote=true` (global config của một số máy) thì `git push`
/// trên branch chưa có upstream sẽ TỰ tạo upstream và thành công, làm case
/// "không có upstream → push fail" không còn tái hiện được.
Future<void> _configIdentity(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
  await _git(['config', 'push.default', 'simple'], cwd);
  await _git(['config', 'push.autoSetupRemote', 'false'], cwd);
}

void main() {
  late Directory tmp;
  late String remotePath; // bare remote
  late String localPath; // local clone (= repo user đang làm việc)

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('git_branch_ahead_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');

    // Bare remote
    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);

    // Local clone + commit đầu tiên + push (tree clean, ahead 0, behind 0)
    await _git(['clone', remotePath, localPath], tmp.path);
    await _configIdentity(localPath);
    File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-m', 'initial'], localPath);
    await _git(['push', '-u', 'origin', 'main'], localPath);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tạo [count] commit local trong [cwd] và KHÔNG push.
  Future<void> commitLocalOnly(String cwd, int count) async {
    for (var i = 0; i < count; i++) {
      File(p.join(cwd, 'local-$i.txt')).writeAsStringSync('c$i\n');
      await _git(['add', '.'], cwd);
      await _git(['commit', '-m', 'local-only-$i'], cwd);
    }
  }

  group('loadBranches ahead count', () {
    test(
        'commit local chưa push → aheadRemote=1, changedFiles=0, behindRemote=0, '
        'hasUpstream=true (regression: push-btn-ahead-detect)', () async {
      // Arrange: đúng repro của bug — 1 commit local, tree clean, remote không
      // có gì mới.
      await commitLocalOnly(localPath, 1);

      // Act
      final result = await GitBranchService.loadBranches(localPath);

      // Assert: aheadRemote là tín hiệu DUY NHẤT cho "cần push" ở trạng thái
      // này; changed=0 + behind=0 nên nếu thiếu ahead thì UI không biết gì.
      expect(result.aheadRemote, 1,
          reason: 'Phải chạy rev-list --count @{upstream}..HEAD; ahead=0 nghĩa '
              'là chưa tính ahead (bug cũ) → UI không báo cần push.');
      expect(result.changedFiles, 0,
          reason: 'Tree clean → changedFiles=0 (nút Commit sẽ bị disable).');
      expect(result.behindRemote, 0,
          reason: 'Remote không có commit mới → behind=0 (nút Pull disable).');
      expect(result.hasUpstream, isTrue);
    });

    test('2 commit local chưa push → aheadRemote=2', () async {
      // Arrange
      await commitLocalOnly(localPath, 2);

      // Act
      final result = await GitBranchService.loadBranches(localPath);

      // Assert: đếm đúng số commit, không phải cờ bool 0/1.
      expect(result.aheadRemote, 2);
    });

    test('clean + đã push hết → aheadRemote=0', () async {
      // Arrange: setUp đã push commit initial, không commit thêm.

      // Act
      final result = await GitBranchService.loadBranches(localPath);

      // Assert: không có gì để push → không hiện nút Push.
      expect(result.aheadRemote, 0);
      expect(result.hasUpstream, isTrue);
    });

    test('branch không có upstream → hasUpstream=false, aheadRemote=0, '
        'không throw', () async {
      // Arrange: branch mới chưa push → `@{upstream}` không tồn tại →
      // `git rev-list` exit 128 (fatal: no upstream configured).
      await _git(['checkout', '-b', 'orphan'], localPath);
      await commitLocalOnly(localPath, 1);

      // Act
      final result = await GitBranchService.loadBranches(localPath);

      // Assert: guard hasUpstream — branch này cần Publish, không phải Push.
      expect(result.hasUpstream, isFalse,
          reason: 'Không có upstream → exit != 0 → hasUpstream phải false.');
      expect(result.aheadRemote, 0,
          reason: 'Không được parse stdout khi lệnh fail (stdout rỗng).');
      expect(result.current, 'orphan');
    });

    test('vừa có commit local chưa push VỪA có file đổi → aheadRemote>0 và '
        'changedFiles>0 (2 field độc lập)', () async {
      // Arrange
      await commitLocalOnly(localPath, 1);
      File(p.join(localPath, 'dirty.txt')).writeAsStringSync('wip\n');

      // Act
      final result = await GitBranchService.loadBranches(localPath);

      // Assert: ahead không được nuốt changed và ngược lại.
      expect(result.aheadRemote, 1);
      expect(result.changedFiles, 1);
    });
  });

  group('pushCurrentBranch', () {
    test('ahead 1 → push thành công và ahead về 0', () async {
      // Arrange
      await commitLocalOnly(localPath, 1);
      expect((await GitBranchService.loadBranches(localPath)).aheadRemote, 1,
          reason: 'Pre-condition: phải đang ahead 1 trước khi push.');

      // Act
      final result = await GitBranchService.pushCurrentBranch(localPath);

      // Assert
      expect(result.success, isTrue, reason: 'Push output: ${result.output}');
      expect(result.output, isNotEmpty);
      final after = await GitBranchService.loadBranches(localPath);
      expect(after.aheadRemote, 0,
          reason: 'Sau push thành công → không còn commit chưa push → nút '
              'Push phải biến mất.');
    });

    test('push bị reject (remote có commit mới, non-fast-forward) → '
        'success=false và output chứa lý do (không nuốt stderr)', () async {
      // Arrange: pusher khác push commit lên remote trước; local commit riêng
      // và KHÔNG fetch → push của local bị reject non-fast-forward.
      final pusherPath = p.join(tmp.path, 'pusher');
      await _git(['clone', remotePath, pusherPath], tmp.path);
      await _configIdentity(pusherPath);
      File(p.join(pusherPath, 'README.md')).writeAsStringSync('v2\n');
      await _git(['add', '.'], pusherPath);
      await _git(['commit', '-m', 'remote-side'], pusherPath);
      await _git(['push', 'origin', 'main'], pusherPath);

      await commitLocalOnly(localPath, 1);

      // Act
      final result = await GitBranchService.pushCurrentBranch(localPath);

      // Assert: git ghi lý do reject ra STDERR → nếu service chỉ đọc stdout thì
      // output rỗng và user không biết vì sao fail ("đừng nuốt exit code").
      expect(result.success, isFalse,
          reason: 'Non-fast-forward → git push exit != 0.');
      expect(result.output, isNotEmpty);
      expect(result.output, startsWith('Push failed:'));
      expect(
        result.output,
        contains(RegExp('reject', caseSensitive: false)),
        reason: 'Phải gộp stderr vào output (git in "! [rejected]" ra stderr); '
            'chỉ có prefix "Push failed" là đã nuốt chi tiết lỗi.\n'
            'output=${result.output}',
      );
    });

    test('branch không có upstream → success=false, output không rỗng',
        () async {
      // Arrange: branch chưa publish → `git push` fatal "no upstream branch".
      await _git(['checkout', '-b', 'orphan'], localPath);
      await commitLocalOnly(localPath, 1);

      // Act
      final result = await GitBranchService.pushCurrentBranch(localPath);

      // Assert
      expect(result.success, isFalse);
      expect(result.output, isNotEmpty,
          reason: 'Phải trả thông tin lỗi cho user, không im lặng.');
      expect(result.output, startsWith('Push failed:'));
    });
  });
}
