// Regression test cho bug `push-btn-ahead-detect` (phần user thấy trực tiếp):
//
// Trong dialog Git Branches, khi tree clean nhưng còn commit local chưa push,
// slot nút Commit hiện nút *disabled* và không có badge nào → không có đường
// nào push từ dialog, commit local bị bỏ quên.
//
// Fix: slot đó đổi thành nút **Push** khi `_needsPush` (hasUpstream && ahead>0
// && changed==0), kèm chip "{n} ahead".
//
// ── Vì sao test viết theo kiểu này (đã kiểm chứng bằng probe, đừng "dọn") ──
// `GitBranchDialog` gọi `GitBranchService` static (không inject/mock được) nên
// test dùng git fixture THẬT làm `path`. Hệ quả:
//
//  1. MỌI thứ (git fixture + `pumpWidget` + vòng chờ) phải nằm TRONG
//     `tester.runAsync`. `Process.run` tạo ở fake-async zone của widget test
//     KHÔNG BAO GIỜ resolve (`Process.start` đặt 1 Timer 0ms → thành FakeTimer
//     không bao giờ fire) → dialog treo mãi ở trạng thái loading. Đã đo:
//     future tạo ngoài runAsync → done=false sau 20 vòng pump.
//  2. KHÔNG dùng `pumpAndSettle`: khi loading dialog render
//     `CircularProgressIndicator` (animation vô hạn) → pumpAndSettle timeout.
//     Dùng vòng `Future.delayed` + `pump` tới khi spinner tắt.
//  3. `textScaler: 0.7`: font test (FlutterTest/Ahem) rộng hơn font thật nên
//     Row title của AlertDialog overflow 3px trong môi trường test (không phải
//     bug app — trong app font thật hẹp hơn, `Spacer` hấp thụ hết). Thu nhỏ
//     text để layout test khớp thực tế.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/widgets/git_branch_dialog.dart';
import 'package:path/path.dart' as p;

/// Chạy 1 lệnh git trong [cwd], fail test nếu exitCode != 0.
Future<void> _git(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
}

void main() {
  late Directory tmp;
  late String remotePath;
  late String localPath;

  setUp(() {
    // CHỈ thao tác đồng bộ ở đây. `await Process.run` trong `setUp` của
    // `testWidgets` chạy ở fake-async zone → treo (xem ghi chú đầu file).
    tmp = Directory.systemTemp.createTempSync('git_branch_dialog_push_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Cây widget tối thiểu để pump dialog: cần l10n delegates cho `context.l10n`.
  /// Locale pin 'en' để label assert ổn định. Các sub-dialog builder là stub —
  /// test này chỉ quan tâm slot nút nào được render.
  Widget wrap(String path) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: const TextScaler.linear(0.7),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: GitBranchDialog(
            path: path,
            displayName: 'fixture',
            currentBranch: 'main',
            branchColor: (_) => Colors.blue,
            onChanged: (_) {},
            pullDialogBuilder: (name, path, {targetBranch, currentBranch}) =>
                const SizedBox.shrink(),
            commitDialogBuilder: (name, path) => const SizedBox.shrink(),
            prDialogBuilder: (name, path, currentBranch) =>
                const SizedBox.shrink(),
            pruneDialogBuilder: (branches) => const SizedBox.shrink(),
          ),
        ),
      );

  /// Dựng fixture git (bare remote + clone đã push commit "initial"), tạo
  /// [aheadCommits] commit local KHÔNG push, tuỳ chọn để lại 1 file chưa
  /// commit ([dirty]), rồi mount dialog và chờ nó load xong.
  ///
  /// Toàn bộ chạy trong `tester.runAsync` — bắt buộc, xem ghi chú đầu file.
  Future<void> mountLoadedDialog(
    WidgetTester tester, {
    int aheadCommits = 0,
    bool dirty = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      Directory(remotePath).createSync(recursive: true);
      await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);
      await _git(['clone', remotePath, localPath], tmp.path);
      await _git(['config', 'user.email', 'test@example.com'], localPath);
      await _git(['config', 'user.name', 'Test'], localPath);
      await _git(['config', 'commit.gpgsign', 'false'], localPath);
      File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
      await _git(['add', '.'], localPath);
      await _git(['commit', '-m', 'initial'], localPath);
      await _git(['push', '-u', 'origin', 'main'], localPath);

      for (var i = 0; i < aheadCommits; i++) {
        File(p.join(localPath, 'local-$i.txt')).writeAsStringSync('c$i\n');
        await _git(['add', '.'], localPath);
        await _git(['commit', '-m', 'local-only-$i'], localPath);
      }
      if (dirty) {
        File(p.join(localPath, 'dirty.txt')).writeAsStringSync('wip\n');
      }

      await tester.pumpWidget(wrap(localPath));

      // Chờ initState → _loadBranches (fetch + ~5 lệnh git) hoàn tất.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
      }
      fail('GitBranchDialog còn loading sau ~5s — git fixture không phản hồi?');
    });
  }

  bool buttonEnabled(WidgetTester tester, String label) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, label))
      .enabled;

  testWidgets(
      'clean tree + ahead>0 → hiện nút Push (enabled), KHÔNG hiện nút Commit '
      '(regression: push-btn-ahead-detect)', (tester) async {
    // Arrange + Act: đúng trạng thái bug — commit local chưa push, tree clean.
    await mountLoadedDialog(tester, aheadCommits: 1);

    // Assert: slot Commit đã hoán thành Push và bấm được.
    expect(find.widgetWithText(FilledButton, 'Push'), findsOneWidget,
        reason: 'Ahead>0 + clean → phải có nút Push; trước fix chỉ có nút '
            'Commit disabled nên không push được từ dialog.');
    expect(buttonEnabled(tester, 'Push'), isTrue);
    expect(find.widgetWithText(FilledButton, 'Commit'), findsNothing,
        reason: 'Không có gì để commit → không render nút Commit song song.');
  });

  testWidgets('ahead>0 → hiện chip "1 ahead"', (tester) async {
    // Arrange + Act
    await mountLoadedDialog(tester, aheadCommits: 1);

    // Assert: status chip là indicator trực quan trong dialog.
    expect(find.text('1 ahead'), findsOneWidget);
  });

  testWidgets(
      'có file đổi (changed>0) → hiện nút Commit enabled, KHÔNG có Push',
      (tester) async {
    // Arrange + Act: vừa ahead vừa dirty → commit trước, push sau (không được
    // cướp slot Commit khi còn thay đổi chưa commit).
    await mountLoadedDialog(tester, aheadCommits: 1, dirty: true);

    // Assert
    expect(find.widgetWithText(FilledButton, 'Commit'), findsOneWidget);
    expect(buttonEnabled(tester, 'Commit'), isTrue);
    expect(find.widgetWithText(FilledButton, 'Push'), findsNothing,
        reason: 'Còn file chưa commit → ưu tiên Commit, chưa hiện Push.');
  });

  testWidgets('clean + ahead==0 → nút Commit disabled (hành vi cũ giữ nguyên)',
      (tester) async {
    // Arrange + Act: repo đã push hết, không có gì thay đổi.
    await mountLoadedDialog(tester);

    // Assert: không regress trạng thái bình thường.
    expect(find.widgetWithText(FilledButton, 'Push'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Commit'), findsOneWidget);
    expect(buttonEnabled(tester, 'Commit'), isFalse);
  });
}
