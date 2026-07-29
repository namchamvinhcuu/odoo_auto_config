// Test cho `GitBranchService.fetchThenDiverge` — helper GỘP `git fetch --quiet`
// + `loadUpstreamDivergence` thành MỘT đơn vị.
//
// ĐÂY LÀ GUARD G1 — lý do tồn tại của cả refactor. Trước đây hai bước này nằm
// rời nhau trong `_syncRepoStatus` (private) và trong provider; xoá bước
// "đo lại sau fetch" thì KHÔNG test nào đỏ (mutation vòng trước: 0 đỏ). Bug đó
// đã ship một lần: đo `behind` mà chưa fetch → đọc remote-tracking ref stale →
// báo `0` một cách tự tin.
//
// Ca cốt lõi: remote đi trước 2 commit, local CHƯA từng fetch. Test assert
// TRƯỚC khi gọi helper rằng `rev-list HEAD..@{upstream}` = 0 (tức nếu helper
// không fetch thì nó chỉ có thể trả 0), rồi mới assert helper trả behind = 2.
//
// Hành vi git đã VERIFY trên máy này (git 2.53.0):
//   - remote URL không tồn tại → `git fetch` rc=128, nhưng `rev-list` với
//     `@{upstream}` vẫn rc=0 (ref local còn đó) ⇒ hasUpstream vẫn true, behind 0
//   - branch không có upstream trong clone có origin → `git fetch` rc=0
//     (fetch origin thành công) ⇒ fetchFailed = false

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
Future<void> _configIdentity(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
}

/// `rev-list --count HEAD..@{upstream}` đo TRỰC TIẾP (không qua service) —
/// dùng để chứng minh trạng thái stale TRƯỚC khi gọi helper.
Future<int> _rawBehind(String cwd) async {
  final r = await Process.run(
    'git',
    ['rev-list', '--count', 'HEAD..@{upstream}'],
    workingDirectory: cwd,
  );
  return int.tryParse((r.stdout as String).trim()) ?? -1;
}

void main() {
  late Directory tmp;
  late String remotePath; // bare remote
  late String localPath; // repo dưới test — KHÔNG tự fetch
  late String pusherPath; // clone khác, push thẳng lên remote

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('git_fetch_diverge_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');
    pusherPath = p.join(tmp.path, 'pusher');

    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);

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

  /// Push [count] commit lên remote từ một clone KHÁC, để local không hề biết.
  Future<void> pushFromElsewhere(int count) async {
    await _git(['clone', remotePath, pusherPath], tmp.path);
    await _configIdentity(pusherPath);
    for (var i = 0; i < count; i++) {
      File(p.join(pusherPath, 'remote-$i.txt')).writeAsStringSync('r$i\n');
      await _git(['add', '.'], pusherPath);
      await _git(['commit', '-m', 'remote-$i'], pusherPath);
    }
    await _git(['push', 'origin', 'main'], pusherPath);
  }

  test(
      'G1: remote đi trước 2 commit + local CHƯA fetch → behind = 2 '
      '(helper PHẢI tự fetch trước khi đo, không đọc ref stale)', () async {
    // Arrange
    await pushFromElsewhere(2);
    // Pre-condition: ref local còn stale ⇒ nếu helper bỏ bước fetch, giá trị duy
    // nhất nó có thể trả là 0. Đây là điều làm test này KHÔNG thể luôn-xanh.
    expect(await _rawBehind(localPath), 0,
        reason: 'fixture sai: local đã fetch sẵn thì test mất ý nghĩa');

    // Act
    final result = await GitBranchService.fetchThenDiverge(localPath);

    // Assert
    expect(result.divergence.behind, 2);
    expect(result.divergence.ahead, 0);
    expect(result.divergence.hasUpstream, isTrue);
    expect(result.fetchFailed, isFalse);
  });

  test(
      'G1: vừa ahead 1 vừa behind 2 (diverged) → cả hai count đúng sau fetch',
      () async {
    // Arrange
    await pushFromElsewhere(2);
    File(p.join(localPath, 'local-only.txt')).writeAsStringSync('l\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-m', 'local-only'], localPath);
    expect(await _rawBehind(localPath), 0, reason: 'fixture sai: đã fetch sẵn');

    // Act
    final result = await GitBranchService.fetchThenDiverge(localPath);

    // Assert
    expect(result.divergence.ahead, 1);
    expect(result.divergence.behind, 2);
    expect(result.fetchFailed, isFalse);
  });

  test('remote không có commit mới → behind = 0, fetchFailed = false',
      () async {
    // Act
    final result = await GitBranchService.fetchThenDiverge(localPath);

    // Assert
    expect(result.divergence, (ahead: 0, behind: 0, hasUpstream: true));
    expect(result.fetchFailed, isFalse);
  });

  test(
      'remote URL không tồn tại → fetchFailed = true, KHÔNG throw '
      '(UI phải cảnh báo thay vì tin con số 0)', () async {
    // Arrange
    await _git(
      ['remote', 'set-url', 'origin', p.join(tmp.path, 'khong-ton-tai.git')],
      localPath,
    );

    // Act
    final result = await GitBranchService.fetchThenDiverge(localPath);

    // Assert
    expect(result.fetchFailed, isTrue);
    // Ref remote-tracking cũ vẫn còn local ⇒ upstream vẫn resolve được.
    expect(result.divergence.hasUpstream, isTrue);
    expect(result.divergence.behind, 0);
  });

  test('branch KHÔNG có upstream → divergence = (0, 0, false), không throw',
      () async {
    // Arrange
    await _git(['checkout', '-q', '-b', 'feature/x'], localPath);
    File(p.join(localPath, 'a.txt')).writeAsStringSync('a\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-m', 'c1'], localPath);

    // Act
    final result = await GitBranchService.fetchThenDiverge(localPath);

    // Assert
    expect(result.divergence, (ahead: 0, behind: 0, hasUpstream: false));
    // Verify thực tế: `git fetch` vẫn thành công (fetch origin), nên fetchFailed
    // là false — thất bại fetch và "không có upstream" là hai chuyện khác nhau.
    expect(result.fetchFailed, isFalse);
  });

  test('thư mục KHÔNG phải git repo → fetchFailed = true, không throw',
      () async {
    // Arrange
    final plain = p.join(tmp.path, 'plain');
    Directory(plain).createSync(recursive: true);

    // Act
    final result = await GitBranchService.fetchThenDiverge(plain);

    // Assert
    expect(result.fetchFailed, isTrue);
    expect(result.divergence, (ahead: 0, behind: 0, hasUpstream: false));
  });
}
