// Regression test cho bug `behind-count-stale-after-pull`:
//
// `loadBranchStatus(path)` trước đây chụp `current = state.valueOrNull` ở ĐẦU
// method, copy TOÀN BỘ các map (branches/changedCount/behindCount/fetchFailed)
// từ snapshot đó, chạy ~4 lệnh `Process.run` git (mỗi cái await → yield event
// loop), rồi cuối ghi `state = AsyncData(current.copyWith(...))` dựa trên
// snapshot CŨ. Khi 2 call `loadBranchStatus` cho 2 path khác nhau chạy cạnh
// tranh, call kết thúc sau ghi đè key của repo KHÁC bằng giá trị STALE trong
// snapshot của nó → badge behind-count không về 0 sau pull.
//
// Fix: method tính giá trị cho RIÊNG `path` vào biến local nullable, cuối đọc
// LẠI `state.valueOrNull` mới nhất rồi merge chỉ 1 key của path đó
// (`{...latest.behindCount, path: behindValue}`). Không còn clobber.
//
// Test dùng git fixture THẬT (bare remote + local clone + pusher push thẳng lên
// remote) — chạm Process.run thật, cần `git` trong PATH. Tái dùng đúng pattern
// fixture của test/other_projects_behind_count_test.dart.

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
    tmp = Directory.systemTemp.createTempSync('other_projects_clobber_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tạo 1 bộ {bare remote, local clone, pusher clone} dưới [tmp]/[name].
  /// local clone có commit "initial" đã push. Trả về path của local clone.
  Future<({String local, String pusher, String remote})> _makeRepo(
      String name) async {
    final remotePath = p.join(tmp.path, '$name-remote.git');
    final localPath = p.join(tmp.path, '$name-local');
    final pusherPath = p.join(tmp.path, '$name-pusher');

    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);

    await _git(['clone', remotePath, localPath], tmp.path);
    await _configIdentity(localPath);
    File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-m', 'initial'], localPath);
    await _git(['push', '-u', 'origin', 'main'], localPath);

    return (local: localPath, pusher: pusherPath, remote: remotePath);
  }

  /// Clone [remote] vào [pusher], tạo [count] commit mới, push thẳng lên remote.
  /// Sau đó local (chưa fetch) sẽ behind [count] commit.
  Future<void> _pushCommits(String remote, String pusher, int count) async {
    await _git(['clone', remote, pusher], tmp.path);
    await _configIdentity(pusher);
    for (var i = 0; i < count; i++) {
      File(p.join(pusher, 'README.md')).writeAsStringSync('v${i + 2}\n');
      await _git(['add', '.'], pusher);
      await _git(['commit', '-m', 'remote-ahead-${i + 1}'], pusher);
    }
    await _git(['push', 'origin', 'main'], pusher);
  }

  /// Mô phỏng "pull": local fetch + merge fast-forward lên upstream để catch up.
  Future<void> _pull(String local) async {
    await _git(['pull', '--ff-only', 'origin', 'main'], local);
  }

  test(
      'behind-count clears to zero after pull '
      '(regression: behind-count-stale-after-pull)', () async {
    // Arrange: remote đi trước local 2 commit → local behind 2.
    final repo = await _makeRepo('repoP');
    await _pushCommits(repo.remote, repo.pusher, 2);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);

    // Seed state có behindCount[path]=2 (badge hiển thị "behind 2") một cách
    // tự nhiên qua chính loadBranchStatus.
    await notifier.loadBranchStatus(repo.local);
    expect(
      container.read(otherProjectsProvider).valueOrNull?.behindCount[repo.local],
      2,
      reason: 'Pre-condition: state phải có behindCount stale = 2 trước pull.',
    );

    // Act: user pull → local catch up với upstream → tải lại branch status.
    await _pull(repo.local);
    await notifier.loadBranchStatus(repo.local);

    // Assert: behind phải về 0, badge không còn stale.
    expect(
      container.read(otherProjectsProvider).valueOrNull?.behindCount[repo.local],
      0,
      reason: 'Sau pull local đã catch up → behindCount[path] phải = 0, '
          'không giữ giá trị stale.',
    );
  });

  test(
      'concurrent loadBranchStatus cho 2 path không clobber lẫn nhau '
      '(regression: behind-count-stale-after-pull)', () async {
    // Arrange: 2 repo độc lập, cả hai đều behind upstream trước pull.
    final repoA = await _makeRepo('repoA');
    final repoB = await _makeRepo('repoB');
    await _pushCommits(repoA.remote, repoA.pusher, 1); // A behind 1
    await _pushCommits(repoB.remote, repoB.pusher, 3); // B behind 3

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    final notifier = container.read(otherProjectsProvider.notifier);

    // Seed behindCount stale cho CẢ HAI path (tuần tự) → state = {A:1, B:3}.
    await notifier.loadBranchStatus(repoA.local);
    await notifier.loadBranchStatus(repoB.local);
    final seeded = container.read(otherProjectsProvider).valueOrNull;
    expect(seeded?.behindCount[repoA.local], 1);
    expect(seeded?.behindCount[repoB.local], 3);

    // Cả hai repo pull → catch up → behind git thật giờ = 0 cho cả hai.
    await _pull(repoA.local);
    await _pull(repoB.local);

    // Act: gọi ĐỒNG THỜI loadBranchStatus cho A và B. Với bug cũ (snapshot toàn
    // bộ map ở đầu), call kết thúc SAU ghi đè key của repo kia bằng giá trị
    // stale trong snapshot của nó → ít nhất 1 path vẫn còn != 0.
    await Future.wait([
      notifier.loadBranchStatus(repoA.local),
      notifier.loadBranchStatus(repoB.local),
    ]);

    // Assert: cả hai phản ánh git thật (0), không path nào bị giữ stale.
    final after = container.read(otherProjectsProvider).valueOrNull;
    expect(
      after?.behindCount[repoA.local],
      0,
      reason: 'A đã pull → behind 0; nếu B clobber A bằng snapshot stale thì '
          'A sẽ giữ giá trị cũ (1).',
    );
    expect(
      after?.behindCount[repoB.local],
      0,
      reason: 'B đã pull → behind 0; nếu A clobber B bằng snapshot stale thì '
          'B sẽ giữ giá trị cũ (3).',
    );
  });
}
