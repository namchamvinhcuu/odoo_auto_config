// Widget test cho `OtherProjectListView` — chế độ LIST của
// [[Features/Other-Projects]] (chế độ GRID có file test riêng:
// `other_project_grid_view_publish_test.dart`).
//
// ── Vì sao file này tồn tại ──
// List view và Grid view là HAI bản render độc lập của cùng một state, mỗi bản tự
// viết lại gate `unpublishedCount > 0` / `aheadCount > 0`. Đúng loại nhân bản đã
// sinh ra 4 bug trong họ này ([[Architecture/Git-Status-Paths]] §Lịch sử cùng họ):
// một surface được sửa, surface kia bị bỏ lại. Grid đã có test từ đợt trước, List
// thì chưa ⇒ xoá cả gate Publish của List vẫn xanh toàn bộ suite.
//
// ── Điều kiện môi trường của widget này (đã ĐỌC CODE, không giả định) ──
//  1. Hàng nút (Pull/Commit/Push/Publish/VSCode/Folder) chỉ render khi
//     `Directory(ws.path).existsSync()` ⇒ phải dùng temp dir THẬT.
//  2. Nút Publish/Push gate CHỈ bằng `state.unpublishedCount[path]` /
//     `state.aheadCount[path]` — **KHÁC grid**, không cần
//     `state.branches.containsKey(path)`. Cái `branches` chỉ gate CHIP branch +
//     các badge bên trong chip. Tooltip Publish đọc `state.branches[path] ?? ''`
//     nên vẫn an toàn khi thiếu key (chuỗi thành `Publish `). Test vẫn set
//     `branches` để tooltip có tên branch thật, và có 1 ca chốt riêng rằng nút
//     Publish KHÔNG phụ thuộc `branches`.
//  3. KHÔNG có `InkWell(onDoubleTap:)` nào trên card list (mở VSCode là một
//     IconButton riêng) ⇒ không có `DoubleTapGestureRecognizer` giữ gesture
//     arena ⇒ tap nút chỉ cần `pump()` 1 frame. Khác grid/tile, nơi phải chuyển
//     `onDoubleTap` sang vùng tên mới đạt được điều đó.
//
// ── Bẫy icon (đã ghi trong vault, đừng "dọn") ──
// `GitActionIcons.push` là `Icons.commit` (glyph commit!). Nút Push ở đây cố ý
// dùng `GitSyncBadge.ahead` để khớp badge. Assert ĐÚNG IconData, vì nút Commit
// luôn hiện với `Icons.commit` nên "vắng Icons.commit" không chứng minh gì.
//
// `OtherProjectListView` là Stateless nhận `OtherProjectsState` trực tiếp ⇒ không
// cần `ProviderScope`, không chạy git.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';
import 'package:odoo_auto_config/screens/other_projects/other_project_list_view.dart';

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

  setUp(() {
    // Path phải TỒN TẠI THẬT: `exists` gate cả hàng nút.
    tmp = Directory.systemTemp.createTempSync('other_project_list_');
    ws = WorkspaceInfo(
      name: 'proj_a',
      path: tmp.path,
      type: 'Odoo',
      description: '',
      createdAt: '2026-07-29',
    );
    pushed = [];
    published = [];
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(OtherProjectsState state) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OtherProjectListView(
            workspaces: [ws],
            state: state,
            onToggleFavourite: (_) {},
            onGitPull: (_) {},
            onGitCommit: (_) {},
            onGitPush: pushed.add,
            onGitPublish: published.add,
            onOpenInVscode: (_) {},
            onOpenInVisualStudio: (_) {},
            onOpenInFileManager: (_) {},
            onEdit: (_) {},
            onSetupNginx: (_) {},
            onRemoveNginx: (_) {},
            onRemove: (_) {},
            onSwitchBranch: (_) {},
            branchColor: (_) => Colors.blue,
            iconForType: (_) => Icons.apps,
            colorForType: (_) => Colors.teal,
          ),
        ),
      );

  /// [ahead] / [unpublished] là hai map độc lập trên cùng path — đúng shape mà
  /// `loadBranchStatus` ghi ra. [withBranch] = false bỏ hẳn key khỏi `branches`
  /// để kiểm gate nút KHÔNG phụ thuộc chip branch.
  OtherProjectsState stateWith({
    String branch = 'feature/x',
    int ahead = 0,
    int unpublished = 0,
    bool hasUpstream = false,
    bool withBranch = true,
  }) =>
      OtherProjectsState(
        workspaces: [ws],
        branches: withBranch ? {ws.path: branch} : const {},
        aheadCount: {ws.path: ahead},
        unpublishedCount: {ws.path: unpublished},
        hasUpstream: {ws.path: hasUpstream},
      );

  /// Card list là một `Row` rất dài (favourite + 6 nút + chip + Spacer +
  /// description + delete) — cửa sổ 800px mặc định làm RenderFlex overflow ⇒
  /// fail vì layout, không vì hành vi.
  Future<void> pumpList(WidgetTester tester, OtherProjectsState state) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(state));
  }

  /// Bấm nút theo tooltip — **1 frame** (không có double-tap recognizer nào trên
  /// card này; nếu ai thêm `onDoubleTap` bọc cả card thì các ca tap dưới đỏ ngay,
  /// đúng như đã xảy ra với tile Workspace và card grid).
  Future<void> tapButton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
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

  testWidgets('unpublishedCount=3 → CÓ nút Publish (+ badge trong chip branch)',
      (tester) async {
    // Arrange + Act: branch chưa từng publish, 3 commit local.
    await pumpList(tester, stateWith(unpublished: 3));

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

    // Assert — badge trong chip (list view hiện số này trong chip branch)
    expect(find.byIcon(GitSyncBadge.unpublished), findsOneWidget);
    expect(find.byTooltip(_unpublishedTooltip(3)), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('unpublishedCount=0 → KHÔNG nút Publish, KHÔNG badge',
      (tester) async {
    // Arrange + Act
    await pumpList(tester, stateWith(unpublished: 0));

    // Assert
    expect(find.byTooltip(_publishTooltip('feature/x')), findsNothing);
    expect(find.byIcon(GitSyncBadge.unpublished), findsNothing);

    // Neo môi trường — nếu thiếu, mọi assert "vắng mặt" ở trên đều xanh giả:
    expect(
      find.byTooltip(_pullTooltip),
      findsOneWidget,
      reason: 'Chốt hàng nút CÓ render (path tồn tại thật ⇒ gate `exists` pass).',
    );
    expect(
      find.text('feature/x'),
      findsOneWidget,
      reason: 'Chốt chip branch CÓ render (branches có key) ⇒ vắng badge là kết '
          'luận thật.',
    );
  });

  testWidgets(
      'aheadCount=2 → nút Push dùng icon GitSyncBadge.ahead '
      '(KHÔNG phải GitActionIcons.push = glyph commit)', (tester) async {
    // Arrange + Act
    await pumpList(tester, stateWith(ahead: 2, hasUpstream: true));

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
    await pumpList(tester, stateWith(unpublished: 1));

    // Act
    await tapButton(tester, _publishTooltip('feature/x'));

    // Assert
    expect(published, [ws]);
    expect(pushed, isEmpty,
        reason: 'Bắt lỗi wiring hoán chỗ Publish ↔ Push (2 nút cạnh nhau, cùng '
            'họ hành động).');
  });

  testWidgets('tap Push → onGitPush gọi đúng workspace đó', (tester) async {
    // Arrange
    await pumpList(tester, stateWith(ahead: 2, hasUpstream: true));

    // Act
    await tapButton(tester, _pushTooltip);

    // Assert
    expect(pushed, [ws]);
    expect(published, isEmpty);
  });

  testWidgets(
      'nút Publish KHÔNG phụ thuộc `state.branches` (khác chip branch)',
      (tester) async {
    // Arrange + Act: chưa đo được tên branch (key vắng) nhưng đã biết có commit
    // chưa publish. Đây là ca dễ regress nếu ai "đồng bộ" list theo grid bằng
    // cách bọc nút vào cùng gate với chip.
    await pumpList(tester, stateWith(unpublished: 2, withBranch: false));

    // Assert: tooltip degrade thành 'Publish ' (branch rỗng) nhưng nút vẫn phải
    // có — mất nút = user không publish được dù có việc để publish.
    expect(find.byTooltip(_publishTooltip('')), findsOneWidget);
    expect(
      find.text('feature/x'),
      findsNothing,
      reason: 'Pre-condition: chip branch KHÔNG render ở ca này.',
    );
  });
}
