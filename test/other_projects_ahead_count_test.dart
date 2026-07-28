// Regression test cho bug `push-btn-ahead-detect` (phần indicator NGOÀI dialog):
//
// Card project ở Other Projects chỉ có badge changed / behind, không có badge
// nào cho "commit local chưa push" → user không kiểm soát được repo nào đang
// ahead. `loadBranchStatus` không tính `@{upstream}..HEAD`.
//
// Fix: `OtherProjectsState.aheadCount` + block `git rev-list --count
// @{upstream}..HEAD` trong `loadBranchStatus`, merge CHỈ key của path đang xử
// lý (giữ pattern chống clobber race của bug `behind-count-stale-after-pull`).
//
// Test dùng git fixture THẬT (bare remote + local clone) — cần `git` trong
// PATH. Tái dùng pattern fixture của test/other_projects_behind_count_test.dart
// + test/other_projects_behind_clobber_test.dart.

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

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('other_projects_ahead_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tạo bộ {bare remote, local clone} tên [name]; local đã có commit
  /// "initial" push lên remote (tree clean, ahead 0). Trả path local clone.
  Future<String> makeRepo(String name) async {
    final remotePath = p.join(tmp.path, '$name-remote.git');
    final localPath = p.join(tmp.path, '$name-local');

    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);

    await _git(['clone', remotePath, localPath], tmp.path);
    await _configIdentity(localPath);
    File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-m', 'initial'], localPath);
    await _git(['push', '-u', 'origin', 'main'], localPath);

    return localPath;
  }

  /// Tạo [count] commit local trong [cwd] và KHÔNG push → ahead = count.
  Future<void> commitLocalOnly(String cwd, int count) async {
    for (var i = 0; i < count; i++) {
      File(p.join(cwd, 'local-$i.txt')).writeAsStringSync('c$i\n');
      await _git(['add', '.'], cwd);
      await _git(['commit', '-m', 'local-only-$i'], cwd);
    }
  }

  /// Khởi tạo notifier qua ProviderContainer rồi chạy loadBranchStatus cho
  /// [path], trả về aheadCount[path] (null = không set).
  Future<int?> aheadCountFor(String path) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);
    await notifier.loadBranchStatus(path);
    return container.read(otherProjectsProvider).valueOrNull?.aheadCount[path];
  }

  test(
      'loadBranchStatus set aheadCount=1 khi repo có commit local chưa push '
      '(regression: push-btn-ahead-detect)', () async {
    // Arrange: tree clean, remote không có gì mới → chỉ ahead khác 0.
    final repo = await makeRepo('repoAhead');
    await commitLocalOnly(repo, 1);

    // Act
    final ahead = await aheadCountFor(repo);

    // Assert: badge "1↑" trên card phụ thuộc key này; null/0 = bug cũ.
    expect(ahead, 1,
        reason: 'Phải chạy rev-list --count @{upstream}..HEAD trong '
            'loadBranchStatus; thiếu → card không có badge chưa-push.');
  });

  test('loadBranchStatus = 0 khi đã push hết', () async {
    // Arrange: repo clean, không commit thêm.
    final repo = await makeRepo('repoClean');

    // Act
    final ahead = await aheadCountFor(repo);

    // Assert
    expect(ahead, 0);
  });

  test(
      'aheadCount đúng cho CẢ HAI repo khi loadBranchStatus chạy song song '
      '(regression: behind-count-clobber-race)', () async {
    // Arrange: 2 repo ahead khác nhau (1 và 3) để phát hiện clobber — nếu
    // snapshot state bị copy wholesale, call kết thúc sau sẽ ghi đè key của
    // repo kia bằng giá trị stale (null → mất badge, hoặc số của chính nó).
    final repoA = await makeRepo('repoA');
    final repoB = await makeRepo('repoB');
    await commitLocalOnly(repoA, 1);
    await commitLocalOnly(repoB, 3);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);

    // Act: gọi ĐỒNG THỜI cho A và B (đúng cách refresh parallel batch dùng).
    await Future.wait([
      notifier.loadBranchStatus(repoA),
      notifier.loadBranchStatus(repoB),
    ]);

    // Assert
    final after = container.read(otherProjectsProvider).valueOrNull;
    expect(after?.aheadCount[repoA], 1,
        reason: 'A ahead 1; nếu B clobber A thì giá trị này sai/mất.');
    expect(after?.aheadCount[repoB], 3,
        reason: 'B ahead 3; nếu A clobber B thì giá trị này sai/mất.');
  });

  test('repo không có upstream → không crash và aheadCount = 0', () async {
    // Arrange: branch mới chưa publish → `@{upstream}` không tồn tại →
    // rev-list exit 128.
    final repo = await makeRepo('repoOrphan');
    await _git(['checkout', '-b', 'orphan'], repo);
    await commitLocalOnly(repo, 2);

    // Act
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);
    await notifier.loadBranchStatus(repo);
    final state = container.read(otherProjectsProvider).valueOrNull;

    // Assert: không throw, branch vẫn load bình thường, ahead ghi tường minh 0.
    expect(state?.branches[repo], 'orphan',
        reason: 'Các field khác vẫn phải load bình thường.');
    expect(state?.aheadCount[repo], 0,
        reason: 'Không có upstream → không có gì push được → phải ghi 0 TƯỜNG '
            'MINH. Để null nghĩa là "giữ map cũ" trong copyWith → badge của '
            'branch trước còn nguyên (xem test stale bên dưới).');
  });

  // ── Regression cho finding 🟠 của flutter-reviewer (đã fix) ──────────────
  // `aheadValue` để null khi rev-list exit != 0 → `copyWith(aheadCount: null)`
  // = "giữ map cũ" → badge "chưa push" + nút Push của branch TRƯỚC còn hiện
  // trên branch mới không có gì để push; bấm Push → `fatal: ... has no
  // upstream branch`.
  //
  // Điểm mấu chốt: phải gọi `loadBranchStatus` HAI LẦN trên CÙNG một path
  // (cùng container) mới lộ bug. Gọi 1 lần với branch không upstream thì map
  // vốn rỗng → test xanh giả.
  test(
      'aheadCount về 0 sau khi switch sang branch KHÔNG có upstream '
      '(regression: stale ahead badge / finding 🟠 reviewer)', () async {
    // Arrange: repo trên `main` ahead 2 → badge hiện "2".
    final repo = await makeRepo('repoStale');
    await commitLocalOnly(repo, 2);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);

    await notifier.loadBranchStatus(repo);
    expect(
      container.read(otherProjectsProvider).valueOrNull?.aheadCount[repo],
      2,
      reason: 'Pre-condition: state phải có aheadCount=2 trước khi switch.',
    );

    // Act: user tạo + switch sang branch mới chưa publish, rồi màn hình refresh
    // branch status cho ĐÚNG path đó (other_projects_screen.onSwitched).
    await _git(['checkout', '-b', 'feature/x'], repo);
    await notifier.loadBranchStatus(repo);

    // Assert: badge phải tắt. Nếu giữ null (bug cũ) → vẫn là 2 → badge + nút
    // Push stale trên branch không có upstream.
    final after = container.read(otherProjectsProvider).valueOrNull;
    expect(after?.branches[repo], 'feature/x',
        reason: 'Pre-condition: đã switch branch thật.');
    expect(after?.aheadCount[repo], 0,
        reason: 'Branch mới không có upstream → không có gì push → badge phải '
            'về 0, KHÔNG giữ 2 của branch cũ.');
  });

  test(
      'aheadCount về 0 khi HEAD detached (regression: stale ahead badge)',
      () async {
    // Arrange: repo ahead 2 (badge "2"), state đã được seed.
    final repo = await makeRepo('repoDetached');
    await commitLocalOnly(repo, 2);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);
    await notifier.loadBranchStatus(repo);
    expect(
      container.read(otherProjectsProvider).valueOrNull?.aheadCount[repo],
      2,
    );

    // Act: checkout thẳng 1 commit → detached HEAD → rev-list @{upstream}..HEAD
    // exit 128 (`fatal: HEAD does not point to a branch`).
    final sha = await Process.run('git', ['rev-parse', 'HEAD'],
        workingDirectory: repo);
    await _git(['checkout', (sha.stdout as String).trim()], repo);
    await notifier.loadBranchStatus(repo);

    // Assert
    final after = container.read(otherProjectsProvider).valueOrNull;
    expect(after?.aheadCount[repo], 0,
        reason: 'Detached HEAD → không có upstream để so → badge phải về 0.');
  });
}
