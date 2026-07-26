// Regression test cho bug `other-projects-no-push-indicator`:
// commit xong nhưng CHƯA push thì tab "Other Projects" không báo gì — vì
// `loadBranchStatus` chỉ đếm behind (`HEAD..@{upstream}`) và số file dirty
// (`git status --porcelain`), KHÔNG hề đếm ahead (`@{upstream}..HEAD`).
// Commit xong working tree sạch → changedCount = 0, behindCount = 0 → không
// badge nào hiện → user tưởng đã push xong.
//
// Fix: thêm `git rev-list --count @{upstream}..HEAD` (sau `git fetch`) và map
// `OtherProjectsState.aheadCount`.
//
// Dùng git fixture THẬT (bare remote + local clone) — chạm Process.run thật,
// cần `git` trong PATH; cùng pattern với other_projects_behind_count_test.

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

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('other_projects_ahead_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');

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

  /// Chạy loadBranchStatus rồi đọc state của path fixture.
  Future<OtherProjectsState> statusFor(String path) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);
    await notifier.loadBranchStatus(path);
    return container.read(otherProjectsProvider).valueOrNull!;
  }

  /// Tạo commit local (working tree sạch sau đó) nhưng KHÔNG push.
  Future<void> commitLocally(String cwd, String content) async {
    File(p.join(cwd, 'README.md')).writeAsStringSync(content);
    await _git(['add', '.'], cwd);
    await _git(['commit', '-m', 'local work'], cwd);
  }

  test(
      'aheadCount = 1 sau khi commit mà chưa push '
      '(regression: thiếu rev-list @{upstream}..HEAD)', () async {
    // Arrange
    await commitLocally(localPath, 'v2\n');

    // Act
    final state = await statusFor(localPath);

    // Assert: đây chính là tín hiệu "cần push" mà UI dựa vào.
    expect(state.aheadCount[localPath], 1,
        reason: 'Commit chưa push phải cho ahead=1; ahead=0/null nghĩa là '
            'provider không đếm @{upstream}..HEAD (bug cũ).');
    // Working tree sạch + remote không đổi → hai badge kia phải tắt, nên nếu
    // thiếu ahead thì UI hoàn toàn im lặng.
    expect(state.changedCount[localPath], 0);
    expect(state.behindCount[localPath], 0);
  });

  test('aheadCount cộng dồn nhiều commit chưa push', () async {
    // Arrange
    await commitLocally(localPath, 'v2\n');
    await commitLocally(localPath, 'v3\n');

    // Act
    final state = await statusFor(localPath);

    // Assert
    expect(state.aheadCount[localPath], 2);
  });

  test('aheadCount về 0 sau khi push', () async {
    // Arrange
    await commitLocally(localPath, 'v2\n');
    await _git(['push', 'origin', 'main'], localPath);

    // Act
    final state = await statusFor(localPath);

    // Assert
    expect(state.aheadCount[localPath], 0);
  });

  test('aheadCount = 0 khi chỉ có file sửa mà chưa commit', () async {
    // Arrange: dirty working tree, chưa commit → chỉ changedCount bật.
    File(p.join(localPath, 'README.md')).writeAsStringSync('dirty\n');

    // Act
    final state = await statusFor(localPath);

    // Assert
    expect(state.aheadCount[localPath], 0);
    expect(state.changedCount[localPath], 1);
  });

  test('loadBranchStatus đồng thời 2 repo không clobber aheadCount', () async {
    // Arrange: repo thứ hai (bare remote riêng), cả hai đều có 1 commit chưa
    // push. Merge per-key trong loadBranchStatus phải giữ được cả hai key.
    final remote2 = p.join(tmp.path, 'remote2.git');
    final local2 = p.join(tmp.path, 'local2');
    Directory(remote2).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remote2], tmp.path);
    await _git(['clone', remote2, local2], tmp.path);
    await _configIdentity(local2);
    File(p.join(local2, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], local2);
    await _git(['commit', '-m', 'initial'], local2);
    await _git(['push', '-u', 'origin', 'main'], local2);

    await commitLocally(localPath, 'v2\n');
    await commitLocally(local2, 'v2\n');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);

    // Act
    await Future.wait([
      notifier.loadBranchStatus(localPath),
      notifier.loadBranchStatus(local2),
    ]);

    // Assert
    final state = container.read(otherProjectsProvider).valueOrNull!;
    expect(state.aheadCount[localPath], 1);
    expect(state.aheadCount[local2], 1);
  });
}
