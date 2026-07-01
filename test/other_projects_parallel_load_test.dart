// Regression test cho perf-fix `loadBranches` parallel-batch:
//
// `loadBranches(workspaces)` trước đây load TUẦN TỰ (await loadBranchStatus
// trong vòng for) → thời gian refresh tăng tuyến tính theo số repo. Fix: load
// SONG SONG theo batch `Future.wait` (batch size _kBatchSize = 8).
//
// Rủi ro parallel hoá: tái phát bug `behind-count clobber` đã fix trước đó —
// nhiều `loadBranchStatus` chạy đồng thời, mỗi cái await Process.run (yield event
// loop), nếu cái nào snapshot toàn bộ map ở đầu rồi ghi đè wholesale thì sẽ
// clobber key của repo khác. `loadBranchStatus` đã được fix merge-per-key
// (re-read state mới nhất, copyWith chỉ 1 key của path mình) nên an toàn.
//
// Test này gọi TRỰC TIẾP `notifier.loadBranches(workspaceList)` (đã expose
// `@visibleForTesting`) thay vì đi qua `reload()`. Cách dựng state: build provider
// với config rỗng (`container.read(otherProjectsProvider.future)` → state non-null,
// workspaces rỗng → KHÔNG ghi gì xuống StorageService), rồi await loadBranches với
// list WorkspaceInfo trỏ vào fixture repo thật. Vì gọi & await thẳng nên KHÔNG cần
// poll timeout, KHÔNG cần HOME override (không ghi config thật của user).
//
// Verify với N repo (kể cả N > batch size để chạy nhiều vòng batch),
// behindCount/changedCount/branches của TẤT CẢ repo đều đúng đồng thời — không
// sót, không clobber.
//
// Test dùng git fixture THẬT (bare remote + local clone + pusher push thẳng lên
// remote) — chạm Process.run thật, cần `git` trong PATH. Tái dùng pattern fixture
// của test/other_projects_behind_clobber_test.dart.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
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

/// Dựng list WorkspaceInfo trỏ vào [paths] để truyền thẳng cho loadBranches.
List<WorkspaceInfo> _workspacesFor(List<String> paths) => [
      for (var i = 0; i < paths.length; i++)
        WorkspaceInfo(
          name: 'ws$i',
          path: paths[i],
          type: 'other',
          description: '',
          createdAt: '2026-01-01',
        ),
    ];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('other_projects_parallel_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tạo 1 bộ {bare remote, local clone, pusher clone} dưới [tmp]/[name].
  /// local clone có commit "initial" đã push. Trả về path của local clone.
  Future<({String local, String pusher, String remote})> makeRepo(
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
  Future<void> pushCommits(String remote, String pusher, int count) async {
    await _git(['clone', remote, pusher], tmp.path);
    await _configIdentity(pusher);
    for (var i = 0; i < count; i++) {
      File(p.join(pusher, 'README.md')).writeAsStringSync('v${i + 2}\n');
      await _git(['add', '.'], pusher);
      await _git(['commit', '-m', 'remote-ahead-${i + 1}'], pusher);
    }
    await _git(['push', 'origin', 'main'], pusher);
  }

  /// Tạo [count] file chưa commit trong local → `git status --porcelain` đếm được.
  void makeDirty(String local, int count) {
    for (var i = 0; i < count; i++) {
      File(p.join(local, 'dirty_$i.txt')).writeAsStringSync('uncommitted\n');
    }
  }

  /// Build provider với config rỗng (không ghi gì) và trả về notifier sẵn sàng.
  Future<OtherProjectsNotifier> buildNotifier(
      ProviderContainer container) async {
    // build() đọc StorageService (read-only) → state non-null; workspaces rỗng
    // nên loadBranches scheduled trong build() là no-op (không chạm git/config).
    await container.read(otherProjectsProvider.future);
    return container.read(otherProjectsProvider.notifier);
  }

  test(
      'loadBranches load song song N repo: behindCount/changedCount/branches '
      'đúng cho TẤT CẢ repo, không clobber, không sót '
      '(regression: behind-count clobber khi parallel loadBranches)', () async {
    // Arrange: 3 repo độc lập, mỗi repo behind upstream + dirty khác nhau.
    final repos = <({String local, String pusher, String remote})>[
      await makeRepo('repo0'),
      await makeRepo('repo1'),
      await makeRepo('repo2'),
    ];
    final behindExpected = [1, 2, 3]; // mỗi repo behind số commit khác nhau
    final dirtyExpected = [0, 2, 1]; // mỗi repo có số file dirty khác nhau
    for (var i = 0; i < repos.length; i++) {
      await pushCommits(repos[i].remote, repos[i].pusher, behindExpected[i]);
      makeDirty(repos[i].local, dirtyExpected[i]);
    }
    final paths = repos.map((r) => r.local).toList();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = await buildNotifier(container);

    // Act: loadBranches load song song theo batch.
    await notifier.loadBranches(_workspacesFor(paths));
    final s = container.read(otherProjectsProvider).requireValue;

    // Assert: mọi repo phản ánh đúng git thật, không key nào bị clobber/sót.
    for (var i = 0; i < repos.length; i++) {
      expect(s.behindCount[paths[i]], behindExpected[i],
          reason: 'repo$i behind phải = ${behindExpected[i]} '
              '(clobber/sót sẽ làm sai key này).');
      expect(s.changedCount[paths[i]], dirtyExpected[i],
          reason: 'repo$i changedCount phải = ${dirtyExpected[i]}.');
      expect(s.branches[paths[i]], 'main',
          reason: 'repo$i branch phải = main.');
    }
  });

  test(
      'loadBranches với số repo > batch size (9 > 8) chạy nhiều vòng batch đúng '
      '(regression: parallel loadBranches batching)', () async {
    // Arrange: 9 repo (> _kBatchSize=8) → loadBranches chạy 2 vòng batch.
    // Mỗi repo behind = index+1 để mỗi key có giá trị riêng, dễ phát hiện
    // clobber chéo giữa các batch.
    const n = 9;
    final repos = <({String local, String pusher, String remote})>[];
    for (var i = 0; i < n; i++) {
      final r = await makeRepo('batch$i');
      await pushCommits(r.remote, r.pusher, i + 1); // behind = i+1
      repos.add(r);
    }
    final paths = repos.map((r) => r.local).toList();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = await buildNotifier(container);

    // Act
    await notifier.loadBranches(_workspacesFor(paths));
    final s = container.read(otherProjectsProvider).requireValue;

    // Assert: cả 9 key đúng → vòng batch sau không clobber vòng trước.
    for (var i = 0; i < n; i++) {
      expect(s.behindCount[paths[i]], i + 1,
          reason: 'repo batch$i (vòng ${i < 8 ? 1 : 2}) behind phải = ${i + 1}; '
              'sai = clobber chéo giữa các batch.');
      expect(s.branches[paths[i]], 'main');
    }
    expect(s.behindCount.length, n,
        reason: 'Phải có đúng $n key behindCount, không sót repo nào.');
  });

  test(
      'loadBranches bỏ qua an toàn workspace không phải git repo (không có .git) '
      'trong khi vẫn load đúng repo hợp lệ cùng batch', () async {
    // Arrange: 1 repo git hợp lệ + 1 thư mục KHÔNG phải git (no .git).
    final repo = await makeRepo('valid');
    await pushCommits(repo.remote, repo.pusher, 2); // behind 2
    final nonGit = Directory(p.join(tmp.path, 'plain-dir'))
      ..createSync(recursive: true);
    File(p.join(nonGit.path, 'note.txt')).writeAsStringSync('not a repo\n');

    final paths = [repo.local, nonGit.path];

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = await buildNotifier(container);

    // Act
    await notifier.loadBranches(_workspacesFor(paths));
    final s = container.read(otherProjectsProvider).requireValue;

    // Assert: repo hợp lệ load đúng; non-git path không tạo key (skip an toàn,
    // không crash, không clobber repo hợp lệ).
    expect(s.behindCount[repo.local], 2,
        reason: 'repo hợp lệ vẫn phải load đúng dù cùng batch với non-git path.');
    expect(s.behindCount.containsKey(nonGit.path), false,
        reason: 'workspace không phải git repo phải bị skip, không tạo key.');
    expect(s.branches.containsKey(nonGit.path), false);
  });
}
