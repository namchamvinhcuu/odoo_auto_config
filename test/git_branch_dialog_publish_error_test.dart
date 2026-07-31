// Regression test cho hậu quả USER-FACING của `try/catch` trong
// `_GitBranchDialogState._publishBranch` (`lib/widgets/git_branch_dialog.dart:550`).
//
// ── Bug được canh ──
// `GitBranchService.publishBranch` THROW `ProcessException` (không phải trả
// `GitResult` exitCode != 0) khi `widget.path` không còn tồn tại — repo bị xoá,
// volume bị unmount (tiền đề này được canh riêng ở
// `test/git_branch_service_publish_branch_test.dart`). Không bắt exception thì
// `_switching = true` và `setDialogRunning(true)` NẰM LẠI vĩnh viễn:
//   • danh sách branch bị thay bằng `CircularProgressIndicator` mãi mãi;
//   • `AppDialog.closeButton` bị disable ⇒ **không đóng được dialog**, ESC cũng
//     bị `PopScope(canPop: false)` chặn ⇒ user phải kill app.
// Đó là lý do ca này tồn tại: mutation xoá `try/catch` phải làm nó ĐỎ.
//
// ── Vì sao mount qua `AppDialog.show`, không pump `GitBranchDialog` trần ──
// `context.setDialogRunning` tìm `_DialogProcessScope` bằng
// `getInheritedWidgetOfExactType` và **im lặng no-op** khi không có scope
// (`app_constants.dart:182`). Mount dialog trần (như
// `git_branch_dialog_push_button_test.dart` làm — nó không cần cơ chế này) thì
// nút đóng LUÔN enabled ⇒ mọi assert "đóng được" thành xanh-giả. Test này vì vậy
// đi qua `AppDialog.show` thật, và còn tự kiểm chứng scope sống bằng một
// self-check trước khi assert (xem `assertCloseButtonTracksScope`).
//
// ── Bẫy fake-async (vault: Knowledge-Base/Skill-Test-Real-Process-In-Widget-Test) ──
// `Process.run`/`Process.start` tạo trong fake-async zone của `testWidgets`
// KHÔNG BAO GIỜ resolve ⇒ TOÀN BỘ fixture + `pumpWidget` + vòng chờ + assert nằm
// trong MỘT `tester.runAsync`, và không dùng `pumpAndSettle` (spinner vô hạn).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
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
    // CHỈ thao tác đồng bộ ở đây (await Process.run trong setUp của testWidgets
    // chạy ở fake-async zone → treo).
    tmp = Directory.systemTemp.createTempSync('git_branch_dialog_publish_err_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Context nằm BÊN TRONG dialog (dưới `_DialogProcessScope`) — dùng cho
  /// self-check cơ chế, chỉ qua API công khai (`setDialogRunning`).
  BuildContext? insideDialog;

  /// App chủ: một nút mở `GitBranchDialog` bằng `AppDialog.show` — đúng đường
  /// production, nên `_DialogProcessScope` có thật.
  Widget host(String path, String currentBranch) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            // Font test rộng hơn font thật → tránh overflow giả (xem note của
            // git_branch_dialog_push_button_test.dart).
            textScaler: const TextScaler.linear(0.7),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppDialog.show<void>(
                context: ctx,
                builder: (dialogCtx) => Builder(
                  builder: (inner) {
                    insideDialog = inner;
                    return GitBranchDialog(
                      path: path,
                      displayName: 'fixture',
                      currentBranch: currentBranch,
                      branchColor: (_) => Colors.blue,
                      onChanged: (_) {},
                      pullDialogBuilder:
                          (name, path, {targetBranch, currentBranch}) =>
                              const SizedBox.shrink(),
                      commitDialogBuilder: (name, path) =>
                          const SizedBox.shrink(),
                      prDialogBuilder: (name, path, currentBranch) =>
                          const SizedBox.shrink(),
                      pruneDialogBuilder: (branches) => const SizedBox.shrink(),
                    );
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

  /// Nút X đóng dialog có bấm được không (đọc widget công khai, không private
  /// state). `AppDialog.closeButton` render `IconButton(onPressed: null)` khi
  /// dialog đang chạy process.
  bool closeEnabled(WidgetTester tester) {
    final button = find.ancestor(
      of: find.byIcon(Icons.close),
      matching: find.byType(IconButton),
    );
    expect(button, findsOneWidget, reason: 'dialog phải có đúng 1 nút đóng');
    return tester.widget<IconButton>(button).onPressed != null;
  }

  /// Chứng minh nút đóng THẬT SỰ phản ánh `_DialogProcessScope` trong cây vừa
  /// mount — nếu thiếu bước này, assert "close enabled" ở cuối test có thể xanh
  /// chỉ vì cơ chế không được nối (no-op) chứ không vì `catch` chạy đúng.
  Future<void> assertCloseButtonTracksScope(WidgetTester tester) async {
    insideDialog!.setDialogRunning(true);
    await tester.pump();
    expect(closeEnabled(tester), isFalse,
        reason: 'Scope phải sống: setDialogRunning(true) ⇒ nút đóng disabled. '
            'Nếu ca này xanh-sai (luôn enabled) thì assert cuối test vô nghĩa.');

    insideDialog!.setDialogRunning(false);
    await tester.pump();
    expect(closeEnabled(tester), isTrue);
  }

  /// Bơm frame + chờ thật cho tới khi [done] đúng, tối đa ~[maxMs].
  Future<bool> waitFor(
    WidgetTester tester,
    bool Function() done, {
    int maxMs = 5000,
  }) async {
    for (var i = 0; i * 50 < maxMs; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      if (done()) return true;
    }
    return false;
  }

  testWidgets(
      'MỞ dialog trên repo không còn tồn tại → không treo ngay lúc mở: spinner '
      'tắt, nút đóng dùng được, VÀ có message lỗi (regression: catch trong '
      '_loadBranches)', (tester) async {
    // `_loadBranches` chạy từ `initState` ⇒ đây là lối treo NẶNG hơn
    // `_publishBranch`: dialog treo ngay khi mở, và trước fix không có catch nào
    // set `_message` ⇒ spinner im lặng, X disabled, ESC bị `PopScope` chặn,
    // KHÔNG một dòng lỗi. Vì vậy assert (3) — có message — là phần không được bỏ.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      // Arrange: path CHƯA TỪNG tồn tại — với `Process.run` thì không phân biệt
      // được với "repo vừa bị xoá / volume vừa unmount", cùng một
      // ProcessException. Cố ý KHÔNG dựng repo rồi `deleteSync(recursive: true)`:
      // reviewer nêu ca đó có thể đỏ oan trên Windows vì file lock (dir vừa được
      // dùng làm `workingDirectory`), mà ở đây không cần xoá gì để tái hiện.
      final gone = p.join(tmp.path, 'never-existed');
      expect(Directory(gone).existsSync(), isFalse);

      // Act: mở dialog trỏ vào path đó.
      await tester.pumpWidget(host(gone, 'main'));
      await tester.tap(find.text('open'));
      await tester.pump();

      final reported = await waitFor(
        tester,
        () => find.textContaining('ProcessException').evaluate().isNotEmpty,
      );

      // Assert (1): không treo.
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: '`_loading` còn true thì dialog chỉ là một spinner.');

      // Assert (2): đóng được — hậu quả nặng nhất (ESC cũng bị PopScope chặn).
      expect(closeEnabled(tester), isTrue);

      // Assert (3): user biết VÌ SAO. Đây là điểm khác biệt so với bug
      // `_publishBranch`: ở đó ít nhất còn danh sách branch cũ để nhìn; ở đây
      // không có message thì dialog trắng trơn, không dấu vết gì.
      expect(reported, isTrue,
          reason: 'catch PHẢI set `_message` — chỉ reset `_loading` thì user thấy '
              'một dialog rỗng và không hiểu chuyện gì.');
      // ...và phải là khung ĐỎ. Không có assert này thì bỏ `_isError = true`
      // trong catch vẫn xanh, mà khung message dùng
      // `(_isError ? Colors.red : Colors.green)` (git_branch_dialog.dart:1171)
      // ⇒ app báo "thành công" bằng màu xanh cho một lần load đã fail.
      final loadBox = tester
          .widget<Container>(
            find
                .ancestor(
                  of: find.textContaining('ProcessException'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(loadBox.color, Colors.red.withValues(alpha: 0.1));

      // Self-check chống xanh-giả — CỐ Ý đặt SAU các assert trên: nếu chạy
      // trước, `setDialogRunning(false)` của nó sẽ tự dọn cờ đang mắc và che
      // đúng cái bug này. Ở đây nó chỉ để chứng minh nút đóng thật sự đọc
      // `_DialogProcessScope` trong cây vừa mount (tức "enabled" là trạng thái
      // ĐO ĐƯỢC, không phải hằng số).
      await assertCloseButtonTracksScope(tester);
    });
  });

  testWidgets(
      'publish khi repo đã bị xoá → dialog KHÔNG bị treo: hiện lỗi, nút đóng '
      'dùng được lại, danh sách branch trở về (regression: catch trong '
      '_publishBranch)', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // MỘT runAsync bao trọn fixture + pump + assert (bắt buộc, xem note đầu file).
    await tester.runAsync(() async {
      // ── Arrange: repo có branch `feature/x` CHƯA lên remote ⇒ tile của nó
      // render nút Publish.
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
      await _git(['checkout', '-b', 'feature/x'], localPath);

      await tester.pumpWidget(host(localPath, 'feature/x'));
      await tester.tap(find.text('open'));
      await tester.pump();

      final loaded = await waitFor(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      expect(loaded, isTrue, reason: 'dialog còn loading sau ~5s?');

      // Pre-condition 1: cơ chế nút đóng có thật (chống xanh-giả).
      await assertCloseButtonTracksScope(tester);

      // Pre-condition 2: nút Publish của `feature/x` đang hiển thị và bấm được.
      final publishButton = find.ancestor(
        of: find.byTooltip('Publish feature/x'),
        matching: find.byType(IconButton),
      );
      expect(publishButton, findsOneWidget,
          reason: 'branch chưa lên remote ⇒ phải có nút Publish để bấm.');
      expect(tester.widget<IconButton>(publishButton).onPressed, isNotNull);

      // Repo biến mất SAU khi dialog đã load — mô phỏng repo bị xoá / volume
      // unmount. `publishBranch` sẽ throw ProcessException thay vì trả GitResult.
      Directory(localPath).deleteSync(recursive: true);

      // ── Act
      await tester.tap(publishButton);
      final reported = await waitFor(
        tester,
        () => find.textContaining('ProcessException').evaluate().isNotEmpty,
      );

      // ── Assert (1): KHÔNG bị treo — đây là hậu quả nặng nhất, nên assert
      // trước để mutation xoá catch đỏ ngay ở đúng claim này.
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: '`_switching` còn true thì cả danh sách branch bị thay bằng '
              'spinner và không nút git nào bấm được nữa.');
      expect(closeEnabled(tester), isTrue,
          reason: 'setDialogRunning(false) trong catch là thứ duy nhất mở lại nút '
              'X; thiếu nó thì ESC cũng bị PopScope chặn ⇒ phải kill app.');

      // ── Assert (2): user THẤY được chuyện gì xảy ra, và thấy đó là lỗi.
      expect(reported, isTrue,
          reason: 'Không bắt exception thì không có message nào được set — '
              'dialog chỉ đứng im với spinner, user không biết vì sao.');
      final messageText = find.textContaining('ProcessException');
      final box = tester
          .widget<Container>(
            find
                .ancestor(of: messageText, matching: find.byType(Container))
                .first,
          )
          .decoration as BoxDecoration;
      expect(box.color, Colors.red.withValues(alpha: 0.1),
          reason: 'Khung message phải là biến thể ĐỎ (_isError = true) — xanh ở '
              'đây nghĩa là app báo "thành công" cho một lần publish đã fail.');

      // ── Assert (3): thử lại được — nút Publish trở lại và bấm được.
      final publishAgain = find.ancestor(
        of: find.byTooltip('Publish feature/x'),
        matching: find.byType(IconButton),
      );
      expect(publishAgain, findsOneWidget);
      expect(tester.widget<IconButton>(publishAgain).onPressed, isNotNull,
          reason: 'Người dùng phải thử lại được (vd sau khi mount lại volume).');
    });
  });
}
