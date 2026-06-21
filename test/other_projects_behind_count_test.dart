// Regression test cho bug `other-projects-refresh-no-pull`:
// `loadBranchStatus` không phát hiện remote có commit mới (behind) vì tính
// `git rev-list --count HEAD..@{upstream}` mà KHÔNG `git fetch` trước, nên
// remote-tracking ref `@{upstream}` còn stale → behindCount = 0.
//
// Fix: thêm `git fetch --quiet` NGAY TRƯỚC block "Behind remote".
//
// Test này dùng git fixture THẬT (bare remote + local clone + pusher push
// commit thẳng lên remote không qua local) — chạm Process.run thật, cần `git`
// trong PATH. Tái hiện đúng repro loop trong diagnosis:
//   [A] CHƯA fetch  → rev-list HEAD..@{upstream} = 0   (bug)
//   [B] SAU fetch   → = 1                               (đã fix)

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';
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
  late String localPath; // local clone (= workspace "Other Project")
  late String pusherPath; // clone khác, push commit thẳng lên remote

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('other_projects_behind_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');
    pusherPath = p.join(tmp.path, 'pusher');

    // Bare remote
    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);

    // Local clone + commit đầu tiên + push
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

  /// Helper: khởi tạo notifier qua ProviderContainer (build() đọc storage
  /// thật nhưng trả state non-null; ta seed riêng path fixture qua
  /// loadBranchStatus), rồi đọc behindCount của fixture path.
  Future<int?> behindCountFor(String path) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);
    await notifier.loadBranchStatus(path);
    return container.read(otherProjectsProvider).valueOrNull?.behindCount[path];
  }

  /// Helper: chạy loadBranchStatus rồi trả về fetchFailed[path].
  Future<bool?> fetchFailedFor(String path) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);
    await notifier.loadBranchStatus(path);
    return container.read(otherProjectsProvider).valueOrNull?.fetchFailed[path];
  }

  test(
      'loadBranchStatus phát hiện behind sau khi pusher push commit lên remote '
      '(regression: fetch trước rev-list)', () async {
    // Arrange: pusher clone, tạo commit MỚI, push thẳng lên remote.
    // Local KHÔNG fetch → @{upstream} của local còn trỏ commit cũ.
    await _git(['clone', remotePath, pusherPath], tmp.path);
    await _configIdentity(pusherPath);
    File(p.join(pusherPath, 'README.md')).writeAsStringSync('v2\n');
    await _git(['add', '.'], pusherPath);
    await _git(['commit', '-m', 'remote-ahead'], pusherPath);
    await _git(['push', 'origin', 'main'], pusherPath);

    // Act
    final behind = await behindCountFor(localPath);

    // Assert: nếu fix đúng (fetch trước rev-list) → local thấy 1 commit behind.
    // Nếu thiếu fetch (bug cũ) → behind = 0 → test FAIL.
    expect(behind, 1,
        reason: 'Phải fetch trước rev-list HEAD..@{upstream} để thấy commit '
            'mới trên remote; behind=0 nghĩa là chưa fetch (bug cũ).');
  });

  test('loadBranchStatus = 0 khi remote không có commit mới', () async {
    // Arrange: không ai push thêm gì sau khi local đã up-to-date.

    // Act
    final behind = await behindCountFor(localPath);

    // Assert: up-to-date → không behind.
    expect(behind, 0);
  });

  test('fetchFailed=false khi git fetch thành công (remote hợp lệ)', () async {
    // Arrange: localPath đã clone từ bare remote hợp lệ (setUp) → fetch OK.

    // Act
    final failed = await fetchFailedFor(localPath);

    // Assert
    expect(failed, isFalse,
        reason: 'Remote hợp lệ → git fetch exit 0 → fetchFailed phải false.');
  });

  test('fetchFailed=true khi git fetch thất bại (remote không tồn tại)',
      () async {
    // Arrange: repo độc lập CÓ commit + branch để loadBranchStatus chạy tới
    // block fetch, nhưng remote origin trỏ tới đường dẫn KHÔNG tồn tại nên
    // `git fetch` exit != 0. Dùng file transport (local path) để fail nhanh,
    // không prompt credential.
    final brokenPath = p.join(tmp.path, 'broken');
    await _git(['init', '-b', 'main', brokenPath], tmp.path);
    await _configIdentity(brokenPath);
    File(p.join(brokenPath, 'README.md')).writeAsStringSync('x\n');
    await _git(['add', '.'], brokenPath);
    await _git(['commit', '-m', 'initial'], brokenPath);
    final missingRemote = p.join(tmp.path, 'nonexistent-remote.git');
    await _git(['remote', 'add', 'origin', missingRemote], brokenPath);

    // Act
    final failed = await fetchFailedFor(brokenPath);

    // Assert
    expect(failed, isTrue,
        reason: 'Remote không tồn tại → git fetch exit != 0 → fetchFailed true.');
  });
}
