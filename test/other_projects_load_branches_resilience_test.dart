// Regression test cho bug `git-branch-badge-slow-load` (2 vấn đề, xem
// [[Fix-History/Refresh-Sequential-To-Parallel]] và
// [[Fix-History/Workspace-Open-Slow-Git-Fetch]]):
//
// 1. Badge branch/status biến mất cho ĐA SỐ project: `loadBranches` cũ chia
//    workspace thành batch tuần tự (`for` + `await Future.wait(...)` từng
//    batch). Nếu 1 `loadBranchStatus` throw TRƯỚC khi vào try/catch của chính
//    nó (vd `existsSync()` throw permission-denied) thì exception văng ra khỏi
//    for-loop → mọi batch SAU không bao giờ chạy — các project đứng SAU trong
//    danh sách vĩnh viễn không có badge, dù chẳng có gì sai với chính chúng.
//    Fix: worker-pool concurrency-capped, MỖI lời gọi `loadBranchStatus` trong
//    worker được bọc try/catch riêng — 1 path lỗi không làm dừng cả pool.
//
// 2. Load chậm: các batch chạy TUẦN TỰ với nhau (batch N+1 đợi batch N xong
//    hết, kể cả khi batch N chỉ còn 1 repo chậm) → tổng thời gian tăng gần
//    tuyến tính theo số batch thay vì chỉ phụ thuộc repo CHẬM NHẤT trong mỗi
//    "đợt" workerCount đồng thời.
//
// Test 1 (bắt buộc) dùng subclass override `loadBranchStatus` (ném lỗi cho
// đúng 1 path ở GIỮA danh sách N > _kBatchSize=8 item) để verify TẤT CẢ path
// khác — kể cả các path đứng SAU path lỗi trong list order — vẫn được gọi
// đúng 1 lần. Không cần dựng git fixture thật: `loadBranches`'s bug/fix nằm ở
// tầng điều phối (worker-pool + try/catch), không phải tầng git-status, nên
// override thẳng `loadBranchStatus` là mock đúng boundary (tránh chạm
// Process.run/git thật cho việc không liên quan tới business logic đang test).
//
// Test 2 (optional theo yêu cầu, vẫn viết vì khả thi) đo tương đối: N=16 repo
// (đúng 2 "đợt" workerCount=8) mỗi cái delay D=60ms → tổng thời gian phải gần
// 2*D (worker-pool đồng thời), KHÔNG PHẢI 16*D (tuần tự) hay 2 batch cứng nối
// tiếp nhau chờ item chậm nhất của batch trước xong mới bắt đầu batch sau.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';

/// Dựng list WorkspaceInfo với path fixture (không cần tồn tại trên đĩa —
/// notifier bên dưới override hẳn `loadBranchStatus` nên không chạm
/// filesystem/git thật cho các path này).
List<WorkspaceInfo> _workspacesFor(List<String> paths) => [
      for (var i = 0; i < paths.length; i++)
        WorkspaceInfo(
          name: 'fixture$i',
          path: paths[i],
          type: 'other',
          description: '',
          createdAt: '2026-01-01',
        ),
    ];

/// Notifier con override `loadBranchStatus`: ghi nhận lời gọi cho các path
/// trong [trackedPaths] (bỏ qua path lạ — build() thật của lớp cha vẫn tự
/// schedule 1 lần `loadBranches` nền đọc workspace THẬT từ StorageService của
/// máy đang chạy test; lọc theo [trackedPaths] để lần chạy nền đó không làm
/// nhiễu số đếm của chính test), và THROW cho đúng [throwingPath].
class _ThrowingOnOnePathNotifier extends OtherProjectsNotifier {
  _ThrowingOnOnePathNotifier({
    required this.trackedPaths,
    required this.throwingPath,
  });

  final Set<String> trackedPaths;
  final String throwingPath;
  final List<String> calls = [];

  @override
  Future<void> loadBranchStatus(String path) async {
    if (!trackedPaths.contains(path)) return;
    calls.add(path);
    if (path == throwingPath) {
      throw Exception('simulated loadBranchStatus failure for $path');
    }
  }
}

/// Notifier con đo timing: mỗi `loadBranchStatus` cho path đã track delay
/// [delay] rồi return — dùng để verify pool chạy song song, không tuần tự.
class _DelayedNotifier extends OtherProjectsNotifier {
  _DelayedNotifier({required this.trackedPaths, required this.delay});

  final Set<String> trackedPaths;
  final Duration delay;
  int calls = 0;

  @override
  Future<void> loadBranchStatus(String path) async {
    if (!trackedPaths.contains(path)) return;
    calls++;
    await Future.delayed(delay);
  }
}

void main() {
  test(
      'loadBranches: 1 path throw giữa danh sách KHÔNG chặn các path sau nó '
      '(regression: git-branch-badge-slow-load — badge biến mất khi 1 repo lỗi)',
      () async {
    // Arrange: N=13 (> _kBatchSize=8, đủ để tràn sang "đợt" thứ 2 của worker
    // pool) fixture path, path ở index 6 (giữa đợt đầu) sẽ throw.
    const n = 13;
    const throwingIndex = 6;
    final paths = [for (var i = 0; i < n; i++) '/fixture/repo-$i'];
    final throwingPath = paths[throwingIndex];

    final notifier = _ThrowingOnOnePathNotifier(
      trackedPaths: paths.toSet(),
      throwingPath: throwingPath,
    );
    final container = ProviderContainer(overrides: [
      otherProjectsProvider.overrideWith(() => notifier),
    ]);
    addTearDown(container.dispose);
    // Trigger build() (đọc StorageService thật, read-only) rồi lấy đúng
    // instance notifier đã override ở trên.
    await container.read(otherProjectsProvider.future);

    // Act: gọi thẳng loadBranches với list N path, 1 trong đó sẽ throw.
    // Với bug cũ (exception văng khỏi for-loop batch-tuần-tự), các path đứng
    // SAU throwingIndex sẽ KHÔNG BAO GIỜ được gọi. await không được throw ra
    // ngoài — mỗi lời gọi trong worker đã tự try/catch.
    await notifier.loadBranches(_workspacesFor(paths));

    // Assert: TẤT CẢ N path đều được gọi đúng 1 lần — kể cả path SAU
    // throwingIndex trong list order (đây là điều bug cũ làm sai).
    expect(notifier.calls.length, n,
        reason: '1 path throw không được làm các path khác bị bỏ sót; '
            'thực tế gọi được ${notifier.calls.length}/$n path.');
    expect(notifier.calls.toSet(), paths.toSet(),
        reason: 'Phải có đủ mọi path, không trùng không thiếu.');
    for (var i = throwingIndex + 1; i < n; i++) {
      expect(notifier.calls.contains(paths[i]), true,
          reason: 'repo-$i đứng SAU path lỗi (index $throwingIndex) trong '
              'list order vẫn phải được xử lý — đây chính là bug cũ (batch '
              'tuần tự bị chặn đứng khi 1 batch throw).');
    }
  });

  test(
      'loadBranches: N=16 repo (2 đợt workerCount=8) chạy XẤP XỈ 2 lần delay '
      'của 1 item, KHÔNG PHẢI 16 lần (regression: batch tuần tự → chậm tuyến tính)',
      () async {
    // Arrange: N=16 = đúng 2 "đợt" của worker pool (workerCount=8). Mỗi
    // loadBranchStatus giả delay 60ms mô phỏng git fetch network I/O.
    const n = 16;
    const delay = Duration(milliseconds: 60);
    final paths = [for (var i = 0; i < n; i++) '/fixture/timing-$i'];

    final notifier = _DelayedNotifier(trackedPaths: paths.toSet(), delay: delay);
    final container = ProviderContainer(overrides: [
      otherProjectsProvider.overrideWith(() => notifier),
    ]);
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);

    // Act
    final stopwatch = Stopwatch()..start();
    await notifier.loadBranches(_workspacesFor(paths));
    stopwatch.stop();

    // Assert: đúng 16 lời gọi đã chạy (sanity trước khi đo timing).
    expect(notifier.calls, n);

    // Sequential (bug cũ, batch tuần tự nối tiếp KHÔNG đồng thời trong cùng
    // đợt) sẽ mất ~16*60ms = 960ms. Worker-pool đồng thời (8 worker) chỉ mất
    // ~2*60ms = 120ms cộng overhead lịch trình. Ngưỡng 400ms nằm giữa —
    // thấp hơn NHIỀU so với 960ms tuần tự, cao hơn thoải mái so với ~120ms lý
    // thuyết để tránh flaky trên máy chậm/CI, nhưng vẫn đủ chặt để bug tuần
    // tự (960ms) chắc chắn fail ngưỡng này.
    expect(stopwatch.elapsedMilliseconds, lessThan(400),
        reason: 'Worker-pool phải chạy song song (~2x delay = ~120ms), '
            'không phải tuần tự (~16x delay = ~960ms). Đo được: '
            '${stopwatch.elapsedMilliseconds}ms.');
  });
}
