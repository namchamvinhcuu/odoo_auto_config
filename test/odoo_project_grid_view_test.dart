// Widget test cho `OdooProjectGridView` — grid CHÍNH của app (Odoo Projects).
//
// ── Vì sao file này tồn tại (surface thứ BA của cùng một bug) ──
// Bug gesture arena đã được sửa ở `RepoTile` (Odoo Workspace) và
// `OtherProjectGridView` (Other Projects) ở đợt 3, nhưng grid này — **cùng cấu
// hình `InkWell(onTap + onDoubleTap)` bọc card có 5 IconButton con** — bị bỏ sót
// ở cả 2 đợt. Nếu để nguyên thì 2 grid trông y hệt nhau mà hành vi khác nhau:
// grid Other Projects phản hồi ngay, grid Odoo Projects trễ ~300ms và biến 2
// click nhanh thành "mở VSCode".
//
// Cơ chế (đã đo ở đợt 3, không suy diễn): `DoubleTapGestureRecognizer` **hold**
// gesture arena ngay từ pointer-down ⇒ tap vào IconButton con chỉ được xử lý sau
// khi `kDoubleTapTimeout` (300ms) trôi qua; và nếu có tap thứ 2 trong 300ms thì
// double-tap **thắng** arena ⇒ recognizer của nút con bị reject ⇒ chạy
// `onOpenInVscode` thay vì 2 nút được bấm. Số đo verbatim trên tile:
// `Expected: {'pull': 1, 'pr': 1}` / `Actual: {'vscode': 1}`.
//
// ── Điều kiện môi trường của widget này (đã ĐỌC CODE, không giả định) ──
//  1. `OdooProjectGridView` là **Stateless**, nhận `List<ProjectInfo>` + 13
//     callback. KHÔNG có `state` object nào, KHÔNG cần `ProviderScope`, không
//     chạy git/Process.
//  2. `exists = Directory(proj.path).existsSync()` gate **nút Workspace + nút
//     Git Commit** và gate cả `onDoubleTap` ⇒ phải dùng temp dir THẬT.
//  3. Nút Browser chỉ hiện khi `proj.hasNginx` (`nginxSubdomain` không rỗng) —
//     các ca dưới không cần nó nên để null (4 nút: star / Info / Workspace /
//     Commit).
//  4. Hàng nút là `Wrap`, không phải `Row` ⇒ không có rủi ro RenderFlex overflow
//     ngang như 2 file test kia.
//
// ── Tap phải 1 FRAME (đây là GUARD, không phải tiện dụng) ──
// `tapButton` chỉ `pump()` một frame: không có duration nghĩa là "không có timer
// nào phải hết hạn thì callback mới chạy". Nếu ca nào cần `pump(400ms)` mới xanh
// thì arena fix đã hỏng — ĐỪNG nới test cho qua, báo lại main.

import 'dart:io';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/screens/odoo_projects/odoo_project_grid_view.dart';

/// Label tooltip (locale 'en') — nguồn: `lib/l10n/app_en.arb`.
const _infoTooltip = 'Project Info';
const _workspaceTooltip = 'Workspace View';
const _commitTooltip = 'Git Commit';

void main() {
  late Directory tmp;

  /// Ghi payload, không chỉ đếm: bắt được cả lỗi gọi đúng số lần nhưng sai
  /// project (grid render nhiều card, callback nào cũng nhận `proj`).
  late List<ProjectInfo> vscoded;
  late List<ProjectInfo> selected;
  late List<ProjectInfo> infoed;
  late List<ProjectInfo> committed;
  late List<ProjectInfo> workspaced;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('odoo_project_grid_');
    vscoded = [];
    selected = [];
    infoed = [];
    committed = [];
    workspaced = [];
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// [exists] = false → path KHÔNG tồn tại ⇒ `onDoubleTap` là null và 2 nút
  /// Workspace/Commit bị ẩn (đúng gate của widget).
  ProjectInfo project({String name = 'proj_a', bool exists = true}) =>
      ProjectInfo(
        name: name,
        path: exists ? tmp.path : '${tmp.path}/khong-ton-tai',
        description: '',
        httpPort: 8069,
        longpollingPort: 8072,
        createdAt: '2026-07-29',
      );

  Widget wrap(ProjectInfo proj) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OdooProjectGridView(
            projects: [proj],
            onToggleFavourite: (_) {},
            onShowInfo: infoed.add,
            onOpenWorkspace: workspaced.add,
            onGitPull: (_) {},
            onGitCommit: committed.add,
            onSelectivePull: (_) {},
            onSelect: selected.add,
            onOpenInVscode: vscoded.add,
            onOpenInFileManager: (_) {},
            onOpenInTerminal: (_) {},
            onOpenInBrowser: (_) {},
            onRemove: (_) {},
          ),
        ),
      );

  /// 1200 logical px → 4 cột → card 294x294 (đo được, xem ca layout dưới).
  Future<void> pumpGrid(WidgetTester tester, ProjectInfo proj) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(proj));
  }

  /// Bấm nút theo tooltip — **1 frame duy nhất** (xem ghi chú đầu file).
  Future<void> tapButton(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }

  /// Double-tap: 2 tap cách nhau 50ms (> kDoubleTapMinTime 40ms, <
  /// kDoubleTapTimeout 300ms) rồi chờ recognizer chốt.
  Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(position);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));
  }

  Future<void> doubleTap(WidgetTester tester, Finder target) =>
      doubleTapAt(tester, tester.getCenter(target));

  testWidgets(
      'tap nút Git Commit → callback chạy đúng 1 lần trong 1 FRAME '
      '(guard: không recognizer nào hold gesture arena)', (tester) async {
    // Arrange
    final proj = project();
    await pumpGrid(tester, proj);

    // Act: KHÔNG có `pump(kDoubleTapTimeout)` ở đây — đó là điểm của ca này.
    await tapButton(tester, _commitTooltip);

    // Assert
    expect(committed, [proj]);
    expect(
      vscoded,
      isEmpty,
      reason: 'Bấm 1 nút không được biến thành mở VSCode.',
    );
    expect(selected, isEmpty,
        reason: 'Click nút không được rơi xuống card và đổi selection.');
  });

  testWidgets('tap nút Info → callback chạy đúng 1 lần trong 1 FRAME',
      (tester) async {
    // Arrange: nút Info hiện bất kể `exists`, nên đây là ca guard rẻ nhất.
    final proj = project();
    await pumpGrid(tester, proj);

    // Act
    await tapButton(tester, _infoTooltip);

    // Assert
    expect(infoed, [proj]);
    expect(committed, isEmpty, reason: 'Bắt lỗi wiring hoán chỗ Info ↔ Commit.');
    expect(vscoded, isEmpty);
  });

  // Ca REGRESSION cho đúng bug của đợt 4.
  //
  // Trước fix (mutant M19 đo lại được): `DoubleTapGestureRecognizer` của card
  // gom 2 click nhanh thành một double-tap ⇒ **cả 2 lệnh đều không chạy** và IDE
  // mở ra thay thế. Không exception, không cảnh báo `warnIfMissed` — user chỉ
  // thấy "app không phản hồi".
  testWidgets(
      'tap 2 nút KHÁC NHAU liên tiếp trong <300ms → cả 2 callback chạy, KHÔNG '
      'mở VSCode (regression: double-tap arena)', (tester) async {
    // Arrange
    final proj = project();
    await pumpGrid(tester, proj);

    // Act: 50ms — nằm gọn trong kDoubleTapTimeout, đúng nhịp click thật của user
    // đang thao tác nhanh (Info rồi Workspace View).
    await tester.tap(find.byTooltip(_infoTooltip));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip(_workspaceTooltip));
    await tester.pump(const Duration(milliseconds: 50));

    // Assert
    expect(infoed, [proj], reason: 'Nút Info phải nhận đúng click của nó.');
    expect(workspaced, [proj],
        reason: 'Nút Workspace View phải nhận đúng click của nó.');
    expect(
      vscoded,
      isEmpty,
      reason: '`onOpenInVscode` chạy ở đây = arena regression đã quay lại '
          '(đo được ở tile: Actual == {vscode: 1}).',
    );
  });

  testWidgets('double-tap TÊN PROJECT → onOpenInVscode 1 lần', (tester) async {
    // Arrange
    final proj = project();
    await pumpGrid(tester, proj);

    // Act
    await doubleTap(tester, find.text('proj_a'));

    // Assert
    expect(vscoded, [proj]);
    expect(
      selected,
      isEmpty,
      reason: 'Double-tap thắng arena ⇒ không được vừa mở VSCode vừa select.',
    );
  });

  testWidgets(
      'double-tap vùng KHÁC của card (dòng ports) → KHÔNG mở VSCode, chỉ select '
      '(hành vi MỚI, cố ý)', (tester) async {
    // Arrange: dòng "8069 / 8072" nằm ngay dưới hàng tên, ngoài GestureDetector.
    final proj = project();
    await pumpGrid(tester, proj);

    // Act
    await doubleTap(tester, find.text('8069 / 8072'));

    // Assert
    expect(
      vscoded,
      isEmpty,
      reason: 'Trước fix, `onDoubleTap` nằm trên InkWell bọc CẢ card ⇒ double-tap '
          'ở bất cứ đâu cũng mở VSCode. Nay chỉ vùng tên làm việc đó.',
    );
    expect(
      selected,
      [proj, proj],
      reason: 'Không còn recognizer tranh arena ⇒ mỗi tap là một onTap của card.',
    );
  });

  testWidgets(
      'path KHÔNG tồn tại → double-tap tên KHÔNG mở VSCode (guard `exists` giữ '
      'nguyên sau khi chuyển onDoubleTap)', (tester) async {
    // Arrange: `exists == false` ⇒ `onDoubleTap` là null.
    final proj = project(exists: false);
    await pumpGrid(tester, proj);
    // Pre-condition: chứng minh đúng là nhánh `exists == false` (2 nút bị ẩn),
    // không phải card chưa render.
    expect(find.byTooltip(_workspaceTooltip), findsNothing);
    expect(find.byTooltip(_commitTooltip), findsNothing);
    expect(find.byTooltip(_infoTooltip), findsOneWidget,
        reason: 'Nút Info không phụ thuộc `exists` ⇒ card CÓ render.');

    // Act
    await doubleTap(tester, find.text('proj_a'));

    // Assert
    expect(
      vscoded,
      isEmpty,
      reason: 'Mở VSCode ở path không tồn tại là lệnh chắc chắn fail — guard này '
          'có từ trước và phải sống sót qua việc di chuyển onDoubleTap.',
    );
  });

  // ───────── T10: vùng double-tap rộng bằng CẢ HÀNG, không chỉ chữ ─────────
  //
  // `SizedBox(width: double.infinity)` bọc `Text(proj.name)` là thứ được kiểm ở
  // đây. Reviewer SUY từ layout rằng thiếu nó thì target chỉ rộng bằng glyph
  // (`Column` cho constraint **loose**, khác `Row`+`Expanded` của tile). 2 ca
  // dưới **ĐO** điều đó thay vì tin lời:
  //   - ca 1 đo constraint: dòng ports (cùng Column, KHÔNG có SizedBox) rộng
  //     134.8px trong khi hàng tên rộng 262px = trọn bề rộng trong padding.
  //     Nếu Column cho constraint tight thì 2 số này bằng nhau ⇒ claim của
  //     reviewer sai. Số đo xác nhận claim ĐÚNG.
  //   - ca 2 double-tap tại mép trái hàng tên, và **tự chứng minh** điểm đó nằm
  //     ngoài vùng glyph bằng `getMinIntrinsicWidth` của chính RenderParagraph
  //     (không hardcode toạ độ, không đoán bề rộng chữ).

  testWidgets(
      'hàng tên rộng trọn card, dòng ports thì không '
      '(đo constraint loose của Column — cơ sở của SizedBox width: infinity)',
      (tester) async {
    // Arrange
    await pumpGrid(tester, project());

    // Act
    final card = tester.getRect(find.byType(Card));
    final name = tester.getRect(find.text('proj_a'));
    final ports = tester.getRect(find.text('8069 / 8072'));

    // Assert
    expect(
      name.width,
      card.width - 32,
      reason: 'Padding card là AppSpacing.md (16) mỗi bên ⇒ hàng tên phải chiếm '
          'trọn 262px còn lại. Thiếu SizedBox thì nó co về bề rộng chữ.',
    );
    expect(
      ports.width,
      lessThan(name.width),
      reason: 'Dòng ports là Text ANH EM trong cùng Column nhưng KHÔNG có '
          'SizedBox ⇒ nó co về glyph (134.8px). Đây là bằng chứng Column cho '
          'constraint loose: nếu tight, 2 số này sẽ bằng nhau và SizedBox là dư.',
    );
  });

  testWidgets(
      'double-tap MÉP TRÁI hàng tên (ngoài vùng chữ) vẫn mở VSCode '
      '(guard cho SizedBox width: infinity)', (tester) async {
    // Arrange: tên 1 ký tự để vùng glyph hẹp và nằm giữa (textAlign.center) ⇒
    // mép trái hàng chắc chắn là "khoảng trống" cạnh chữ.
    final proj = project(name: 'p');
    await pumpGrid(tester, proj);

    final nameRect = tester.getRect(find.text('p'));
    // Bề rộng THẬT của glyph, đọc từ chính render object (không đoán, không
    // hardcode): với 1 dòng chữ, min-intrinsic ≈ bề rộng chữ đã vẽ.
    final glyphWidth = tester
        .renderObject<RenderParagraph>(find.text('p'))
        .getMinIntrinsicWidth(double.infinity);
    // Toạ độ tính từ mép CARD (padding 16 + 4px), KHÔNG từ `nameRect`: nameRect
    // co lại khi thiếu SizedBox, nên lấy mốc từ nó sẽ khiến ca này đỏ ở
    // pre-condition thay vì ở assert hành vi — mất luôn bằng chứng cần đo.
    final card = tester.getRect(find.byType(Card));
    final target = Offset(card.left + 20, nameRect.center.dy);

    // Pre-condition: điểm sắp tap phải nằm NGOÀI vùng glyph, nếu không ca này
    // vô nghĩa (nó sẽ xanh kể cả khi không có SizedBox).
    expect(
      target.dx,
      lessThan(nameRect.center.dx - glyphWidth / 2),
      reason: 'Điểm tap ($target) phải ở bên trái vùng chữ '
          '(rộng $glyphWidth, canh giữa ${nameRect.center.dx}). Nếu assert này '
          'đỏ thì đừng "sửa" toạ độ — ca test đã mất ý nghĩa, xem lại layout.',
    );

    // Act
    await doubleTapAt(tester, target);

    // Assert
    expect(
      vscoded,
      [proj],
      reason: 'Thiếu `SizedBox(width: double.infinity)` thì GestureDetector chỉ '
          'rộng bằng chữ ⇒ điểm này rơi xuống card InkWell (không còn '
          'onDoubleTap) ⇒ chỉ select 2 lần, không mở VSCode.',
    );
  });
}
