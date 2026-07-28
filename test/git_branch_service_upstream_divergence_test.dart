// Test cho `GitBranchService.loadUpstreamDivergence` — helper DÙNG CHUNG đếm
// ahead/behind so với `@{upstream}`.
//
// Vì sao file này quan trọng: trước refactor có **3 bản** logic đếm riêng
// (`loadBranches` · `OtherProjectsNotifier.loadBranchStatus` ·
// `_OdooWorkspaceDialogState._computeAheadBehind`) và cả 3 đều từng có cùng bug
// "giữ số của branch trước khi `rev-list` fail" → badge/nút stale. Bản trong
// Odoo Workspace là **private method**, KHÔNG test trực tiếp được (mutation
// M7b vòng 3 không có test nào bắt). Sau khi cả 3 đường gọi helper public này,
// test ở đây **canh gián tiếp cho cả 3** — kể cả đường Odoo Workspace.
//
// Contract cần khoá:
//  - exit != 0 (không upstream / detached / upstream ref bị prune) → cặp số về
//    `(0, 0)` + `hasUpstream: false`, KHÔNG bỏ trống để caller giữ giá trị cũ.
//  - early-return khi lệnh ahead fail chỉ nhằm tránh cập nhật NỬA VỜI; nó
//    KHÔNG được cắt oan lệnh behind khi upstream vẫn tồn tại (ca diverge).
//
// Dùng git fixture THẬT (bare remote + local clone + pusher) — cần `git` trong
// PATH. Helper KHÔNG tự `git fetch` (caller chịu trách nhiệm fetch), nên test
// fetch tường minh trong phần Arrange khi cần remote-tracking ref mới.

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

void main() {
  late Directory tmp;
  late String remotePath; // bare remote
  late String localPath; // repo user đang làm việc
  late String pusherPath; // clone khác, push thẳng lên remote

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('upstream_divergence_');
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

  /// [count] commit local trong [cwd], KHÔNG push → ahead tăng.
  Future<void> commitLocalOnly(String cwd, int count) async {
    for (var i = 0; i < count; i++) {
      File(p.join(cwd, 'local-$i.txt')).writeAsStringSync('c$i\n');
      await _git(['add', '.'], cwd);
      await _git(['commit', '-m', 'local-only-$i'], cwd);
    }
  }

  /// pusher clone → [count] commit → push thẳng lên remote, rồi local `fetch`
  /// (helper không tự fetch) → behind tăng.
  Future<void> remoteAdvances(int count) async {
    await _git(['clone', remotePath, pusherPath], tmp.path);
    await _configIdentity(pusherPath);
    for (var i = 0; i < count; i++) {
      File(p.join(pusherPath, 'remote-$i.txt')).writeAsStringSync('r$i\n');
      await _git(['add', '.'], pusherPath);
      await _git(['commit', '-m', 'remote-side-$i'], pusherPath);
    }
    await _git(['push', 'origin', 'main'], pusherPath);
    await _git(['fetch', '--quiet'], localPath);
  }

  test('2 commit local chưa push → (ahead 2, behind 0, hasUpstream true)',
      () async {
    // Arrange
    await commitLocalOnly(localPath, 2);

    // Act
    final d = await GitBranchService.loadUpstreamDivergence(localPath);

    // Assert
    expect(d.ahead, 2);
    expect(d.behind, 0);
    expect(d.hasUpstream, isTrue);
  });

  test('remote đi trước 3 commit → (ahead 0, behind 3, hasUpstream true)',
      () async {
    // Arrange
    await remoteAdvances(3);

    // Act
    final d = await GitBranchService.loadUpstreamDivergence(localPath);

    // Assert
    expect(d.ahead, 0);
    expect(d.behind, 3);
    expect(d.hasUpstream, isTrue);
  });

  test(
      'diverge cả hai chiều (local 1, remote 2) → ahead 1 VÀ behind 2 '
      '(early-return không được cắt oan lệnh behind)', () async {
    // Arrange: local commit riêng 1 cái, remote đi trước 2 cái → hai nhánh
    // tách nhau. Đây là ca chứng minh early-return chỉ chặn khi KHÔNG có
    // upstream, chứ không bỏ qua lệnh behind khi lệnh ahead trả về > 0.
    await commitLocalOnly(localPath, 1);
    await remoteAdvances(2);

    // Act
    final d = await GitBranchService.loadUpstreamDivergence(localPath);

    // Assert: cả hai số phải đúng cùng lúc.
    expect(d.ahead, 1,
        reason: 'Local có 1 commit chưa push.');
    expect(d.behind, 2,
        reason: 'Remote có 2 commit local chưa có; nếu helper bail out sớm '
            'hoặc bỏ lệnh behind thì số này sẽ là 0.');
    expect(d.hasUpstream, isTrue);
  });

  test('branch KHÔNG có upstream → (0, 0, hasUpstream false)', () async {
    // Arrange: branch mới chưa publish, có commit → nếu helper vẫn đếm bằng
    // đường khác thì ahead sẽ != 0.
    await _git(['checkout', '-b', 'feature/x'], localPath);
    await commitLocalOnly(localPath, 2);

    // Act
    final d = await GitBranchService.loadUpstreamDivergence(localPath);

    // Assert: cặp số phải về 0 TƯỜNG MINH — đây chính là giá trị mà 3 caller
    // ghi đè lên badge/nút để không còn stale.
    expect(d.hasUpstream, isFalse);
    expect(d.ahead, 0);
    expect(d.behind, 0);
  });

  test('detached HEAD → (0, 0, hasUpstream false), không throw', () async {
    // Arrange: checkout thẳng 1 commit → `fatal: HEAD does not point to a
    // branch` (exit 128).
    await commitLocalOnly(localPath, 1);
    final sha = await Process.run('git', ['rev-parse', 'HEAD'],
        workingDirectory: localPath);
    await _git(['checkout', (sha.stdout as String).trim()], localPath);

    // Act
    final d = await GitBranchService.loadUpstreamDivergence(localPath);

    // Assert
    expect(d.hasUpstream, isFalse);
    expect(d.ahead, 0);
    expect(d.behind, 0);
  });

  test('clean + đã push hết → (0, 0, hasUpstream true)', () async {
    // Arrange: setUp đã push commit initial, không làm gì thêm.

    // Act
    final d = await GitBranchService.loadUpstreamDivergence(localPath);

    // Assert: hasUpstream true phân biệt rõ với ca "không có upstream" — cùng
    // cặp số 0/0 nhưng ý nghĩa UI khác nhau (Push vs Publish).
    expect(d.ahead, 0);
    expect(d.behind, 0);
    expect(d.hasUpstream, isTrue);
  });
}
