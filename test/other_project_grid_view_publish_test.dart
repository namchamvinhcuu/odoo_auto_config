// Widget test cho `OtherProjectGridView` — card của [[Features/Other-Projects]].
//
// Khoá phần WIRING UI của `unpublishedCount` (badge + nút Publish): provider đã
// có test riêng (`other_projects_unpublished_count_test.dart`) chứng minh CON SỐ
// đúng, nhưng "số đúng mà card không hiện gì / hiện nút sai" là đúng lớp bug đã
// ship 3 lần trong họ này ([[Architecture/Git-Status-Paths]] §Lịch sử cùng họ).
//
// ── 2 điều kiện môi trường của widget này (không có thì test xanh giả) ──
//  1. Hàng git-status chỉ render khi `state.branches.containsKey(ws.path)`.
//  2. Hàng nút chỉ render khi `Directory(ws.path).existsSync()` ⇒ phải dùng temp
//     dir THẬT làm `WorkspaceInfo.path` (widget đọc filesystem trực tiếp).
//
// ── Bẫy icon (đã ghi trong vault, đừng "dọn") ──
// `GitActionIcons.push` là `Icons.commit` (glyph commit!). Nút Push trên card cố
// ý dùng `GitSyncBadge.ahead` để khớp badge. Test assert ĐÚNG IconData của nút
// Push, vì nút Commit luôn hiện với `Icons.commit` nên "vắng Icons.commit"
// không chứng minh được gì.
//
// `OtherProjectGridView` là Stateless nhận `OtherProjectsState` trực tiếp ⇒
// không cần `ProviderScope`, không chạy git.
//
// ── Gesture arena: NÚT GIT phải phản hồi trong 1 FRAME (đây là một GUARD) ──
// Card TỪNG bọc mọi thứ trong `InkWell` có `onDoubleTap` (mở VSCode).
// `DoubleTapGestureRecognizer` hold gesture arena từ pointer-down ⇒ tap vào nút
// con chỉ được xử lý sau 300ms. Đo được ở đợt trước: tap + `pump()` 1 frame → 0
// lời gọi; tap + `pump(400ms)` → đúng 1 lời gọi. Trên app thật: nút git trễ
// ~300ms, và 2 click nhanh trên 2 nút khác nhau bị gộp thành double-tap mở VSCode.
//
// Đợt này `onDoubleTap` đã chuyển sang một `GestureDetector` bọc RIÊNG
// `Text(ws.name)`. Vì vậy `tapButton` chỉ `pump()` **1 frame** — nếu ca nào cần
// `pump(400ms)` mới xanh thì arena fix đã hỏng, ĐỪNG nới test cho qua.
// Chỉ tap TRÊN TÊN project mới còn bị hold 300ms (vùng đó không có nút nào).

import 'dart:io';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';
import 'package:odoo_auto_config/screens/other_projects/other_project_grid_view.dart';

/// Label tooltip (locale 'en') — nguồn: `lib/l10n/app_en.arb`.
const _pushTooltip = 'Push';
const _pullTooltip = 'Git Pull';
const _commitTooltip = 'Git Commit';
String _publishTooltip(String branch) => 'Publish $branch';
String _unpublishedTooltip(int n) =>
    '$n commit(s) on a branch not published yet';

void main() {
  late Directory tmp;
  late WorkspaceInfo ws;
  late List<WorkspaceInfo> pushed;
  late List<WorkspaceInfo> published;

  /// Ghi lời gọi của 2 callback liên quan tới gesture arena: mở VSCode
  /// (double-tap) và select (single tap trên card).
  late List<WorkspaceInfo> vscoded;
  late List<WorkspaceInfo> selected;
  late List<WorkspaceInfo> pulled;

  setUp(() {
    // Path phải TỒN TẠI THẬT: `exists` gate cả hàng nút.
    tmp = Directory.systemTemp.createTempSync('other_project_grid_');
    ws = WorkspaceInfo(
      name: 'proj_a',
      path: tmp.path,
      type: 'Odoo',
      description: '',
      createdAt: '2026-07-29',
    );
    pushed = [];
    published = [];
    vscoded = [];
    selected = [];
    pulled = [];
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(OtherProjectsState state) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OtherProjectGridView(
            workspaces: [ws],
            state: state,
            onToggleFavourite: (_) {},
            onGitPull: pulled.add,
            onGitCommit: (_) {},
            onGitPush: pushed.add,
            onGitPublish: published.add,
            onSelect: selected.add,
            onOpenInVscode: vscoded.add,
            onOpenInVisualStudio: (_) {},
            onOpenInFileManager: (_) {},
            onOpenInTerminal: (_) {},
            onEdit: (_) {},
            onSetupNginx: (_) {},
            onRemoveNginx: (_) {},
            onRemove: (_) {},
            onSwitchBranch: (_) {},
            branchColor: (_) => Colors.blue,
            colorForType: (_) => Colors.teal,
          ),
        ),
      );

  /// [ahead] / [unpublished] là hai map độc lập trên cùng path — đúng shape mà
  /// `loadBranchStatus` ghi ra.
  OtherProjectsState stateWith({
    String branch = 'feature/x',
    int ahead = 0,
    int unpublished = 0,
    bool hasUpstream = false,
  }) =>
      OtherProjectsState(
        workspaces: [ws],
        branches: {ws.path: branch},
        aheadCount: {ws.path: ahead},
        unpublishedCount: {ws.path: unpublished},
        hasUpstream: {ws.path: hasUpstream},
      );

  Future<void> pumpGrid(WidgetTester tester, OtherProjectsState state) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(state));
  }

  /// Bấm nút theo tooltip — **1 frame duy nhất**, xem ghi chú đầu file. Đây là
  /// GUARD: không có duration nghĩa là "không có timer nào phải hết hạn".
  Future<void> tapButton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }

  /// Double-tap (2 tap cách nhau 50ms — trong kDoubleTapTimeout, ngoài
  /// kDoubleTapMinTime 40ms). [at] cho phép chỉ định toạ độ cụ thể thay vì tâm
  /// widget (dùng cho ca đo bề rộng vùng double-tap).
  Future<void> doubleTap(WidgetTester tester, Finder target,
      {Offset? at}) async {
    final p = at ?? tester.getCenter(target);
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(p);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));
  }

  /// IconData thật của nút có tooltip [tooltip] (IconButton bọc Icon trong
  /// Tooltip nên phải đi qua descendant).
  IconData iconOf(WidgetTester tester, String tooltip) => tester
      .widget<Icon>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(Icon),
        ),
      )
      .icon!;

  testWidgets('unpublishedCount=3 → badge "3" + nút Publish', (tester) async {
    // Arrange + Act: branch chưa từng publish, 3 commit local.
    await pumpGrid(tester, stateWith(unpublished: 3));

    // Assert — badge
    expect(find.byIcon(GitSyncBadge.unpublished), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip(_unpublishedTooltip(3)), findsOneWidget);

    // Assert — nút
    expect(find.byTooltip(_publishTooltip('feature/x')), findsOneWidget);
    expect(
      iconOf(tester, _publishTooltip('feature/x')),
      GitActionIcons.publish,
    );
    expect(
      find.byTooltip(_pushTooltip),
      findsNothing,
      reason: 'ahead==0 + chưa publish ⇒ Push sẽ fail, chỉ Publish có nghĩa.',
    );
  });

  testWidgets('unpublishedCount=0 → KHÔNG badge, KHÔNG nút Publish',
      (tester) async {
    // Arrange + Act: hàng git-status VẪN render (branches có key) nên vắng badge
    // là kết luận thật, không phải vì hàng chưa được vẽ.
    await pumpGrid(tester, stateWith(unpublished: 0));

    // Assert
    expect(find.byIcon(GitSyncBadge.unpublished), findsNothing);
    expect(find.byTooltip(_publishTooltip('feature/x')), findsNothing);
    expect(
      find.text('feature/x'),
      findsOneWidget,
      reason: 'Chốt hàng git-status có render — nếu không, mọi assert vắng mặt '
          'ở trên đều vô nghĩa (xanh giả).',
    );
    expect(
      find.byTooltip(_pullTooltip),
      findsOneWidget,
      reason: 'Chốt hàng nút có render (path tồn tại thật).',
    );
  });

  testWidgets(
      'ahead=2, unpublished=0 → nút Push dùng icon GitSyncBadge.ahead '
      '(KHÔNG phải GitActionIcons.push = glyph commit)', (tester) async {
    // Arrange + Act
    await pumpGrid(tester, stateWith(ahead: 2, hasUpstream: true));

    // Assert
    expect(find.byTooltip(_pushTooltip), findsOneWidget);
    expect(iconOf(tester, _pushTooltip), GitSyncBadge.ahead);
    expect(
      iconOf(tester, _pushTooltip),
      isNot(GitActionIcons.push),
      reason: 'GitActionIcons.push == Icons.commit ⇒ dùng nó ở đây thì nút Push '
          'trông y hệt nút Commit ngay bên cạnh.',
    );
    expect(
      iconOf(tester, _commitTooltip),
      GitActionIcons.commit,
      reason: 'Nút Commit vẫn giữ glyph commit — nên "vắng Icons.commit" không '
          'phải cách kiểm nút Push.',
    );
    expect(find.byTooltip(_publishTooltip('feature/x')), findsNothing);
  });

  testWidgets('tap Publish → onGitPublish gọi đúng workspace đó', (tester) async {
    // Arrange
    await pumpGrid(tester, stateWith(unpublished: 1));

    // Act
    await tapButton(tester, _publishTooltip('feature/x'));

    // Assert
    expect(published, [ws]);
    expect(pushed, isEmpty);
  });

  testWidgets('tap Push → onGitPush gọi đúng workspace đó', (tester) async {
    // Arrange
    await pumpGrid(tester, stateWith(ahead: 2, hasUpstream: true));

    // Act
    await tapButton(tester, _pushTooltip);

    // Assert
    expect(pushed, [ws]);
    expect(published, isEmpty);
  });

  // ───────────────── gesture arena (bug đợt 3 + hành vi mới) ─────────────────

  testWidgets('double-tap TÊN PROJECT → onOpenInVscode 1 lần', (tester) async {
    // Arrange
    await pumpGrid(tester, stateWith(unpublished: 1));

    // Act
    await doubleTap(tester, find.text('proj_a'));

    // Assert
    expect(vscoded, [ws]);
    expect(
      selected,
      isEmpty,
      reason: 'Double-tap thắng arena ⇒ không được vừa mở VSCode vừa select.',
    );
  });

  testWidgets(
      'double-tap vùng KHÁC của card (chip type) → KHÔNG mở VSCode, chỉ select '
      '(hành vi MỚI, cố ý)', (tester) async {
    // Arrange: chip type ('Odoo') nằm ở góc trên card, ngoài vùng tên project.
    await pumpGrid(tester, stateWith(unpublished: 1));

    // Act
    await doubleTap(tester, find.text('Odoo'));

    // Assert
    expect(
      vscoded,
      isEmpty,
      reason: 'Trước fix, `onDoubleTap` nằm trên InkWell bọc CẢ card ⇒ double-tap '
          'ở bất cứ đâu cũng mở VSCode. Nay chỉ vùng tên làm việc đó.',
    );
    expect(
      selected,
      [ws, ws],
      reason: 'Không còn recognizer tranh arena ⇒ mỗi tap là một onTap của card.',
    );
  });

  testWidgets(
      'double-tap MÉP TRÁI hàng tên (ngoài vùng chữ) vẫn mở VSCode '
      '(guard cho SizedBox width: infinity — đợt 4)', (tester) async {
    // Arrange: `Column` cho constraint LOOSE nên nếu không có
    // `SizedBox(width: double.infinity)`, vùng double-tap chỉ rộng bằng glyph.
    // Tên 1 ký tự + `textAlign.center` ⇒ mép trái hàng chắc chắn là khoảng trống.
    ws = WorkspaceInfo(
      name: 'p',
      path: tmp.path,
      type: 'Odoo',
      description: '',
      createdAt: '2026-07-29',
    );
    await pumpGrid(tester, stateWith(unpublished: 1));

    final nameRect = tester.getRect(find.text('p'));
    // Bề rộng THẬT của chữ, đọc từ render object (không đoán, không hardcode).
    final glyphWidth = tester
        .renderObject<RenderParagraph>(find.text('p'))
        .getMinIntrinsicWidth(double.infinity);
    // Mốc là mép CARD (padding 16 + 4px), KHÔNG phải `nameRect`: nameRect co lại
    // khi thiếu SizedBox ⇒ lấy mốc từ nó thì ca này đỏ ở pre-condition thay vì ở
    // assert hành vi.
    final card = tester.getRect(find.byType(Card));
    final target = Offset(card.left + 20, nameRect.center.dy);

    // Pre-condition: điểm tap phải NGOÀI vùng glyph, nếu không ca này vô nghĩa.
    expect(
      target.dx,
      lessThan(nameRect.center.dx - glyphWidth / 2),
      reason: 'Điểm tap phải ở bên trái vùng chữ (rộng $glyphWidth). Assert này '
          'đỏ ⇒ ca test mất ý nghĩa, đừng "sửa" toạ độ.',
    );

    // Act
    await doubleTap(tester, find.text('p'), at: target);

    // Assert
    expect(vscoded, [ws],
        reason: 'Thiếu SizedBox ⇒ điểm này rơi xuống card InkWell (không còn '
            'onDoubleTap) ⇒ chỉ select 2 lần, không mở VSCode.');
  });

  // Ca REGRESSION cho đúng bug được duyệt sửa ở đợt 3: hai click nhanh trên 2
  // nút KHÁC NHAU từng bị gom thành một double-tap ⇒ cả 2 lệnh git đều không
  // chạy, VSCode mở ra thay thế (đo được `calls == {'vscode': 1}` ở tile).
  testWidgets(
      'tap 2 nút KHÁC NHAU liên tiếp trong <300ms → cả 2 callback chạy, KHÔNG '
      'mở VSCode (regression: double-tap arena)', (tester) async {
    // Arrange: repo có upstream + 2 commit chưa push ⇒ hàng nút là
    // Pull / Commit / Push / Folder. Dùng Pull → Push (2 nút xa nhau nhất trong
    // hàng) thay vì Push → Publish: hai nút đó không bao giờ cùng hiện trên repo
    // thật (gate `hasUpstream` loại trừ nhau) và 5 nút làm Row overflow ở
    // cellWidth mặc định — fail vì layout, không vì gesture.
    await pumpGrid(tester, stateWith(ahead: 2, hasUpstream: true));

    // Act
    await tester.tap(find.byTooltip(_pullTooltip));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip(_pushTooltip));
    await tester.pump(const Duration(milliseconds: 50));

    // Assert
    expect(pulled, [ws], reason: 'Nút Pull phải nhận đúng click của nó.');
    expect(pushed, [ws], reason: 'Nút Push phải nhận đúng click của nó.');
    expect(
      vscoded,
      isEmpty,
      reason: '`onOpenInVscode` chạy ở đây = arena regression đã quay lại.',
    );
    expect(selected, isEmpty,
        reason: 'Click nút không được rơi xuống card và đổi selection.');
  });
}
