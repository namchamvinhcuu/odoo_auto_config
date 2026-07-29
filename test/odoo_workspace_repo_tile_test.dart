// Widget test cho `RepoTile` — tile của [[Features/Odoo-Workspace-View]].
//
// Đây là gap #3 trong [[Architecture/Git-Status-Paths]] §Trạng thái các gap:
// điều kiện "nút git nào hiện" từng nằm trong builder PRIVATE của
// `odoo_workspace_dialog.dart` (~1450 dòng) ⇒ Dart privacy theo file nên test
// không gọi được, mà mount cả dialog thì `initState` kéo theo quét filesystem
// thật + `StorageService` thật + `git fetch` thật (đắt + flaky, xem
// [[Knowledge-Base/Skill-Test-Real-Process-In-Widget-Test]]). Ba bug cùng họ đã
// ship trong đúng vùng mù đó.
//
// Nay tile là widget Stateless public nhận `RepoInfo` + callback ⇒ pump TRỰC
// TIẾP, không mount dialog, không chạy Process nào (nên KHÔNG cần `runAsync` /
// git fixture như test của `GitBranchDialog`).
//
// ── Định vị nút: dùng TOOLTIP, không dùng icon ──
// `GitActionIcons.publish` và `GitSyncBadge.ahead` CÙNG là `Icons.cloud_upload`,
// còn `GitActionIcons.push` lại là `Icons.commit` (bẫy đã ghi trong vault). Tìm
// theo icon sẽ nhập nhằng; tooltip l10n là thứ user thật cũng đọc.
//
// KHÔNG dùng `pumpAndSettle`: trạng thái `loaded: false` render
// `CircularProgressIndicator` (animation vô hạn) → pumpAndSettle timeout.
//
// ── Gesture arena: NÚT GIT phải phản hồi trong 1 FRAME (đây là một GUARD) ──
// Tile TỪNG bọc cả hàng trong `InkWell` có `onDoubleTap` (mở VSCode).
// `DoubleTapGestureRecognizer` **hold** gesture arena ngay từ pointer-down ⇒ đo
// được ở đợt trước: tap nút + `pump()` 1 frame → callback KHÔNG chạy; phải
// `pump(kDoubleTapTimeout + 100ms)` mới chạy. Trên app thật nghĩa là mọi nút git
// trễ ~300ms, và hai click nhanh trên 2 nút KHÁC NHAU bị gộp thành double-tap ⇒
// chạy `onOpenInVscode` thay vì 2 nút đó (đo được `calls == {'vscode': 1}`).
//
// Đợt này `onDoubleTap` đã được chuyển ra khỏi hàng, vào một `GestureDetector`
// bọc RIÊNG `Text(repo.name)`. Vì vậy:
//   - MỌI target ngoài vùng tên (nút git, Checkbox, chip branch) ⇒ `tester.tap` +
//     **`pump()` một frame duy nhất** (`tapNow` / `tapButton`). Nếu ca nào cần
//     `pump(400ms)` mới xanh thì arena fix đã hỏng — ĐỪNG nới test cho qua,
//     báo lại main.
//   - tap/double-tap **trên tên repo** vẫn nằm trong vùng có
//     `DoubleTapGestureRecognizer` ⇒ single tap ở đó vẫn bị hold 300ms ⇒ dùng
//     `tapAndWaitArena`. Đây là hành vi ĐÚNG và có chủ đích: vùng đó không có
//     nút nào, đổi lại double-tap mở VSCode vẫn dùng được.

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/repo_info.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/repo_tile.dart';

/// Label tooltip (locale 'en') — nguồn: `lib/l10n/app_en.arb`.
const _pullTooltip = 'Git Pull';
const _pushTooltip = 'Push';
const _prTooltip = 'PR';
const _removeTooltip = 'Remove from list';
const _fetchFailedTooltip =
    'Fetch failed — remote status may be outdated. Check network/credentials '
    'and retry.';
String _publishTooltip(String branch) => 'Publish $branch';
String _aheadTooltip(int n) => '$n ahead';
String _unpublishedTooltip(int n) =>
    '$n commit(s) on a branch not published yet';

RepoInfo _repo({
  String name = 'addon_a',
  String branch = 'feature/x',
  bool loaded = true,
  bool hasUpstream = true,
  int ahead = 0,
  int behind = 0,
  int changed = 0,
  int unpublished = 0,
  bool fetchFailed = false,
  bool syncing = false,
}) {
  final repo = RepoInfo(name: name, path: '/does/not/need/to/exist/$name')
    ..branch = branch
    ..loaded = loaded
    ..hasUpstream = hasUpstream
    ..aheadCount = ahead
    ..behindCount = behind
    ..changedFiles = changed
    ..unpublishedCount = unpublished
    ..fetchFailed = fetchFailed
    ..syncing = syncing;
  return repo;
}

void main() {
  /// Số lần từng callback được gọi — chốt wiring không bị hoán chỗ.
  late Map<String, int> calls;

  /// GIÁ TRỊ mà `onSelectedChanged` nhận được, theo thứ tự.
  ///
  /// Phải ghi payload, KHÔNG chỉ đếm số lần gọi: selection là chỗ DUY NHẤT
  /// refactor gộp 2 đường có **polarity khác nhau** vào 1 callback (hàng đảo giá
  /// trị `!repo.selected`, Checkbox nhận giá trị mới `v`). Fake chỉ đếm sẽ vẫn
  /// xanh khi ai đó bỏ dấu `!` ⇒ tick UI đảo sai ⇒ bulk action của dialog chạy
  /// trên tập repo SAI + `_saveSelection()` persist tick sai vào
  /// `odoo_auto_config.json`.
  late List<bool> selectedCalls;

  setUp(() {
    calls = <String, int>{};
    selectedCalls = <bool>[];
  });

  void bump(String key) => calls[key] = (calls[key] ?? 0) + 1;

  Widget wrap(RepoInfo repo) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RepoTile(
            repo: repo,
            branchColor: (_) => Colors.blue,
            onSelectedChanged: (v) {
              bump('selected');
              selectedCalls.add(v);
            },
            onOpenInVscode: () => bump('vscode'),
            onOpenBranchDialog: () => bump('branchDialog'),
            onPull: () => bump('pull'),
            onPublish: () => bump('publish'),
            onPush: () => bump('push'),
            onCreatePr: () => bump('pr'),
            onRemove: () => bump('remove'),
          ),
        ),
      );

  /// Tile là một `Row` ngang nhiều nút — cửa sổ test mặc định 800px làm
  /// RenderFlex overflow (fail test vì lý do không liên quan tới hành vi).
  Future<void> pumpTile(WidgetTester tester, RepoInfo repo) async {
    tester.view.physicalSize = const Size(1600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(repo));
  }

  /// Tap rồi chờ hết `kDoubleTapTimeout` — CHỈ dùng cho target nằm TRONG vùng
  /// double-tap (tên repo). Ở đó `DoubleTapGestureRecognizer` hold arena nên
  /// single tap thật sự chỉ được xử lý sau timeout; đó là hành vi mong đợi.
  Future<void> tapAndWaitArena(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));
  }

  /// Tap **1 frame duy nhất** — dùng cho mọi target NGOÀI vùng tên repo
  /// (nút git, Checkbox, chip branch).
  ///
  /// Đây là GUARD cho arena fix, không phải tiện dụng: `pump()` không có duration
  /// nghĩa là "không có timer nào phải hết hạn thì callback mới chạy". Nếu ai
  /// trả `onDoubleTap` về `InkWell` bọc cả hàng, mọi ca dùng helper này đỏ ngay.
  Future<void> tapNow(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump();
  }

  /// Bấm nút git theo tooltip (1 frame).
  Future<void> tapButton(WidgetTester tester, String tooltip) =>
      tapNow(tester, find.byTooltip(tooltip));

  testWidgets('loaded=false → chỉ spinner, KHÔNG có nút git nào (Remove vẫn có)',
      (tester) async {
    // Arrange + Act: phase 1 chưa đo xong.
    await pumpTile(tester, _repo(loaded: false, branch: ''));

    // Assert
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip(_pullTooltip), findsNothing);
    expect(find.byTooltip(_pushTooltip), findsNothing);
    expect(find.byTooltip(_prTooltip), findsNothing);
    expect(
      find.byIcon(GitActionIcons.publish),
      findsNothing,
      reason: 'Chưa đo xong thì chưa biết có upstream hay không → không được '
          'mời Publish/Push.',
    );
    expect(
      find.byTooltip(_removeTooltip),
      findsOneWidget,
      reason: 'Remove là always-visible, không phụ thuộc git status.',
    );
  });

  testWidgets(
      'hasUpstream + ahead=0 → KHÔNG có nút Push, vẫn có Pull + PR '
      '(regression: nút Push hiện khi không có gì để push)', (tester) async {
    // Arrange + Act: đúng trạng thái bug #3 — repo đã push hết.
    await pumpTile(tester, _repo(hasUpstream: true, ahead: 0));

    // Assert
    expect(
      find.byTooltip(_pushTooltip),
      findsNothing,
      reason: 'ahead==0 ⇒ bấm Push là no-op; nút phải ẩn (bug #3).',
    );
    expect(find.byTooltip(_pullTooltip), findsOneWidget);
    expect(
      find.byTooltip(_prTooltip),
      findsOneWidget,
      reason: 'PR không phụ thuộc ahead — vẫn mở được để tạo PR từ branch đã push.',
    );
    expect(
      find.byIcon(GitActionIcons.publish),
      findsNothing,
      // Assert này chỉ ĐƠN NGHĨA vì ca này có `ahead: 0`:
      // GitActionIcons.publish == GitSyncBadge.ahead == Icons.cloud_upload, nên
      // nếu ai đổi ca này thành ahead>0 thì nó fail vì BADGE, không vì nút
      // Publish. Fail-loud (hướng an toàn) nhưng đừng chẩn sai nguyên nhân.
      reason: 'Có upstream ⇒ không có nút Publish.',
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Nhãn branch: chip này ĐÃ từng bị mất khi copy tile ở đợt trước, mà không
    // test nào canh (xoá cả block chip vẫn xanh). Đồng thời là NEO MÔI TRƯỜNG
    // cho các assert `findsNothing` ở trên — chứng minh tile đã render thật,
    // không phải finder trượt hết.
    expect(find.text('feature/x'), findsOneWidget);
  });

  testWidgets('hasUpstream + ahead=2 → CÓ nút Push + badge ahead "2"',
      (tester) async {
    // Arrange + Act
    await pumpTile(tester, _repo(hasUpstream: true, ahead: 2));

    // Assert
    expect(find.byTooltip(_pushTooltip), findsOneWidget);
    expect(find.byTooltip(_aheadTooltip(2)), findsOneWidget);
    expect(
      find.text('2'),
      findsOneWidget,
      reason: 'Badge phải hiện SỐ commit chưa push, không chỉ hiện icon.',
    );
    expect(find.byTooltip(_prTooltip), findsOneWidget);
  });

  testWidgets(
      'ahead=2 nhưng KHÔNG upstream → badge ahead phải TẮT (số cũ không sống sót)',
      (tester) async {
    // Arrange + Act: `hasUpstream=false` là trạng thái mà ahead vô nghĩa. Badge
    // gate bằng `hasUpstream && ahead>0` — cùng họ với
    // [[Fix-History/Stale-Counts-When-No-Upstream]].
    await pumpTile(tester, _repo(hasUpstream: false, ahead: 2));

    // Assert
    expect(find.byTooltip(_aheadTooltip(2)), findsNothing);
    expect(find.byTooltip(_pushTooltip), findsNothing);
  });

  // ⚠ Ca này ĐỔI có chủ đích ở đợt 3 (`unpublished: 3` là phần thêm vào).
  //
  // Bản cũ pump `hasUpstream: false` với `unpublishedCount` mặc định 0 và chốt
  // "phải CÓ nút Publish" — tức nó **chốt cứng hành vi lệch** mà reviewer đã ghi
  // ở mục Pre-existing: tile Workspace mời Publish bất cứ khi nào `!hasUpstream`,
  // kể cả khi không có commit nào để publish, trong khi card Other Projects gate
  // bằng `unpublishedCount > 0`. Đợt này align 2 surface ⇒ test cũ phải đổi.
  // Đây là lý do chính đáng duy nhất để sửa test đang xanh: **spec đổi**, không
  // phải "test đỏ nên nới cho qua". Mặt âm của gate mới có ca riêng ngay dưới.
  testWidgets(
      'KHÔNG upstream + CÓ commit chưa publish → CÓ nút Publish, KHÔNG Push, '
      'KHÔNG PR', (tester) async {
    // Arrange + Act: branch chưa từng publish, có 3 commit để đẩy.
    await pumpTile(
      tester,
      _repo(hasUpstream: false, branch: 'feature/x', unpublished: 3),
    );

    // Assert
    expect(find.byTooltip(_publishTooltip('feature/x')), findsOneWidget);
    expect(
      find.byTooltip(_pushTooltip),
      findsNothing,
      reason: 'Không upstream ⇒ `git push` fail; Publish là hành động đúng.',
    );
    expect(
      find.byTooltip(_prTooltip),
      findsNothing,
      reason: 'Branch chưa có trên remote ⇒ chưa tạo PR được.',
    );
    expect(find.byTooltip(_pullTooltip), findsOneWidget);
  });

  // ─────────── parity với card Other Projects (việc #3 của đợt 3) ───────────

  testWidgets(
      'KHÔNG upstream + KHÔNG có gì để publish → KHÔNG nút Publish, KHÔNG badge '
      '(parity với card Other Projects)', (tester) async {
    // Arrange + Act: branch mới `checkout -b` nhưng chưa commit gì — không có
    // commit nào để đẩy lên remote.
    await pumpTile(tester, _repo(hasUpstream: false, unpublished: 0));

    // Assert
    expect(
      find.byTooltip(_publishTooltip('feature/x')),
      findsNothing,
      reason: 'Publish trên branch không có commit nào = affordance cho một '
          'no-op. Card Other Projects đã gate bằng chính con số này; tile phải '
          'đọc cùng một số từ cùng một chỗ (loadPublishableCount).',
    );
    expect(
      find.byIcon(GitSyncBadge.unpublished),
      findsNothing,
      reason: 'unpublishedCount == 0 ⇒ không có badge.',
    );
    // Neo môi trường: chứng minh tile ĐÃ render hàng status + hàng nút, nên 2
    // assert "vắng mặt" ở trên là kết luận thật chứ không phải finder trượt hết.
    expect(find.byTooltip(_pullTooltip), findsOneWidget);
    expect(find.byTooltip(_removeTooltip), findsOneWidget);
    expect(find.text('feature/x'), findsOneWidget);
  });

  testWidgets(
      'KHÔNG upstream + unpublished=3 → badge "3" (icon + tooltip) + nút Publish',
      (tester) async {
    // Arrange + Act: branch mới đầy việc — `ahead` là 0 ở đây (không có upstream
    // để mà ahead), nên KHÔNG có badge này thì tile hiện y như repo sạch.
    await pumpTile(tester, _repo(hasUpstream: false, unpublished: 3));

    // Assert — badge
    expect(find.byIcon(GitSyncBadge.unpublished), findsOneWidget);
    expect(
      find.text('3'),
      findsOneWidget,
      reason: 'Badge phải hiện SỐ commit chưa publish, không chỉ icon.',
    );
    expect(
      find.byTooltip(_unpublishedTooltip(3)),
      findsOneWidget,
      reason: 'Tooltip lấy từ ARB `gitBranchUnpublished` — cùng chuỗi card Other '
          'Projects dùng, nên 2 surface không giải thích badge khác nhau.',
    );

    // Assert — nút
    expect(find.byTooltip(_publishTooltip('feature/x')), findsOneWidget);
    expect(
      find.byTooltip(_aheadTooltip(3)),
      findsNothing,
      reason: 'Badge unpublished KHÁC badge ahead: đây là commit chưa có trên '
          'remote NÀO, không phải commit chưa push lên upstream đã có.',
    );
  });

  testWidgets('tap Push → gọi onPush đúng 1 lần (không hoán chỗ callback)',
      (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true, ahead: 1));

    // Act
    await tapButton(tester, _pushTooltip);

    // Assert
    expect(calls['push'], 1);
    expect(
      calls.keys.where((k) => k != 'push'),
      isEmpty,
      reason: 'Chỉ onPush được gọi — bắt lỗi wiring nhầm sang pull/publish/pr.',
    );
  });

  testWidgets('tap Publish → gọi onPublish đúng 1 lần', (tester) async {
    // Arrange: cần `unpublished > 0` mới có nút (gate mới của đợt 3).
    await pumpTile(tester, _repo(hasUpstream: false, unpublished: 2));

    // Act
    await tapButton(tester, _publishTooltip('feature/x'));

    // Assert
    expect(calls['publish'], 1);
    expect(calls['push'], isNull);
  });

  testWidgets('badge changed / behind / fetchFailed hiện đúng', (tester) async {
    // Arrange + Act
    await pumpTile(
      tester,
      _repo(hasUpstream: true, changed: 3, behind: 4, fetchFailed: true),
    );

    // Assert
    expect(find.text('3 ${GitSyncBadge.changed}'), findsOneWidget);
    expect(find.text('4 ${GitSyncBadge.behind}'), findsOneWidget);
    expect(find.byTooltip(_fetchFailedTooltip), findsOneWidget);
  });

  testWidgets('changed=0 / behind=0 / fetch OK → không badge nào', (tester) async {
    // Arrange + Act
    await pumpTile(tester, _repo(hasUpstream: true));

    // Assert
    expect(find.textContaining(GitSyncBadge.changed), findsNothing);
    expect(find.textContaining(GitSyncBadge.behind), findsNothing);
    expect(find.byIcon(Icons.sync_problem), findsNothing);
  });

  // ───────────────────────── selection (đường polarity) ─────────────────────
  //
  // Đây là dòng DUY NHẤT refactor biến đổi logic (8/9 chỗ substitution còn lại
  // chỉ là "gọi callback thay vì gọi method của State"). Hai đường vào cùng một
  // callback nhưng **cực ngược nhau**:
  //   - hàng (InkWell):  onSelectedChanged(!repo.selected)   ← ĐẢO
  //   - Checkbox:        onSelectedChanged(v ?? false)       ← nhận giá trị mới
  // Regress bất kỳ vế nào ⇒ tick UI đảo sai ⇒ bulk action của dialog chạy trên
  // tập repo SAI + `_saveSelection()` persist tick sai vào file config. Assert
  // phải nhắm **giá trị** truyền ra, không phải số lần gọi.

  testWidgets('Checkbox: selected=false → tap → nhận true', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act
    await tapNow(tester, find.byType(Checkbox));

    // Assert
    expect(selectedCalls, [true]);
  });

  testWidgets('Checkbox: selected=true → tap → nhận false', (tester) async {
    // Arrange: tile là Stateless nên `selected` do dialog sở hữu — set sẵn true
    // đúng như dialog truyền vào sau khi restore selection đã lưu.
    final repo = _repo(hasUpstream: true)..selected = true;
    await pumpTile(tester, repo);

    // Act
    await tapNow(tester, find.byType(Checkbox));

    // Assert
    expect(
      selectedCalls,
      [false],
      reason: 'Checkbox truyền GIÁ TRỊ MỚI (`v`), không đảo lần nữa.',
    );
  });

  testWidgets('hàng tile: selected=true → tap → nhận false (đúng vế !selected)',
      (tester) async {
    // Arrange
    final repo = _repo(hasUpstream: true)..selected = true;
    await pumpTile(tester, repo);

    // Act: bấm vào tên repo — vùng của InkWell bọc cả hàng, không phải chip.
    await tapAndWaitArena(tester, find.text('addon_a'));

    // Assert
    expect(
      selectedCalls,
      [false],
      reason: 'Hàng phải ĐẢO trạng thái hiện tại. Bỏ dấu `!` ⇒ nhận `true` ⇒ '
          'bỏ tick không bao giờ có tác dụng.',
    );
  });

  testWidgets('hàng tile: selected=false → tap → nhận true', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act
    await tapAndWaitArena(tester, find.text('addon_a'));

    // Assert
    expect(selectedCalls, [true]);
  });

  // ─────────── các callback còn lại chưa có ca tap (review gap #3) ───────────
  // Ca `tap Push` bắt được hoán chỗ *sang* pull/remove, nhưng không bắt được
  // hoán chỗ *giữa* pull ↔ remove ↔ vscode ↔ branchDialog.

  testWidgets('tap Pull → chỉ onPull', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act
    await tapButton(tester, _pullTooltip);

    // Assert
    expect(calls, {'pull': 1});
  });

  testWidgets('tap Remove → chỉ onRemove', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act
    await tapButton(tester, _removeTooltip);

    // Assert
    expect(calls, {'remove': 1});
  });

  // Nút PR là nút git duy nhất còn lại chưa có ca tap: không có nó, một mutation
  // MỘT CHIỀU (nút PR gọi onPull/onPush) vẫn xanh — hoán 2 chiều thì ca `tap
  // Push` bắt được, hoán 1 chiều thì không ai bắt.
  testWidgets('tap PR → chỉ onCreatePr', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act
    await tapButton(tester, _prTooltip);

    // Assert
    expect(calls, {'pr': 1});
  });

  testWidgets('tap chip branch → chỉ onOpenBranchDialog', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act
    await tapNow(tester, find.text('feature/x'));

    // Assert
    expect(
      calls,
      {'branchDialog': 1},
      reason: 'Chip branch có InkWell riêng — không được rơi xuống hàng và đổi '
          'selection.',
    );
    expect(selectedCalls, isEmpty);
  });

  // ───────────────── gesture arena (bug đợt 3 + hành vi mới) ─────────────────
  //
  // `onDoubleTap` giờ CHỈ bọc `Text(repo.name)`. Ba ca dưới khoá cả 3 mặt của
  // thay đổi đó: nút git phản hồi ngay, vùng tên vẫn mở VSCode, vùng khác của
  // hàng KHÔNG còn mở VSCode nữa (đổi hành vi có chủ đích).

  testWidgets(
      'double-tap TÊN REPO → onOpenInVscode 1 lần (không đổi selection)',
      (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act: hai tap cách nhau > kDoubleTapMinTime (40ms) và < kDoubleTapTimeout.
    await tester.tap(find.text('addon_a'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('addon_a'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));

    // Assert
    expect(calls, {'vscode': 1});
    expect(
      selectedCalls,
      isEmpty,
      reason: 'Double-tap thắng arena ⇒ KHÔNG được vừa mở VSCode vừa đổi tick.',
    );
  });

  testWidgets(
      'double-tap vùng KHÁC của hàng (badge) → KHÔNG mở VSCode, chỉ toggle '
      'selection (hành vi MỚI, cố ý)', (tester) async {
    // Arrange: badge "3 ↑" nằm ngoài vùng tên repo.
    await pumpTile(tester, _repo(hasUpstream: true, changed: 3));

    // Act
    final badge = find.text('3 ${GitSyncBadge.changed}');
    await tester.tap(badge);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(badge);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 100));

    // Assert
    expect(
      calls['vscode'],
      isNull,
      reason: 'Trước fix, `onDoubleTap` nằm trên InkWell bọc CẢ hàng ⇒ double-tap '
          'ở bất cứ đâu cũng mở VSCode. Nay chỉ vùng tên làm việc đó.',
    );
    expect(
      selectedCalls,
      [true, true],
      reason: 'Không còn recognizer nào tranh arena ⇒ mỗi tap là một onTap của '
          'hàng. Tile là Stateless nên `repo.selected` không đổi giữa 2 tap ⇒ cả '
          '2 lần đều truyền `!false == true`.',
    );
  });

  // Ca REGRESSION cho đúng bug được duyệt sửa ở đợt 3.
  //
  // Số đo TRƯỚC fix (đã ghi ở `/tmp/git-tile-test-gaps-tests.md` vòng 1, và
  // xác nhận lại bằng mutant M16 ở đợt này): hai click nhanh trên 2 nút KHÁC
  // NHAU bị `DoubleTapGestureRecognizer` của hàng gom thành một double-tap ⇒
  // `calls == {'vscode': 1}`, tức **cả 2 lệnh git đều không chạy** và IDE mở ra
  // thay thế. Đây là lớp lỗi tệ nhất của arena: không có exception, không có
  // cảnh báo `warnIfMissed`, user chỉ thấy "app không phản hồi".
  testWidgets(
      'tap 2 nút KHÁC NHAU liên tiếp trong <300ms → cả 2 callback chạy, KHÔNG '
      'mở VSCode (regression: double-tap arena)', (tester) async {
    // Arrange
    await pumpTile(tester, _repo(hasUpstream: true));

    // Act: khoảng cách 50ms — nằm gọn trong kDoubleTapTimeout (300ms), đúng
    // nhịp click thật của user đang thao tác nhanh.
    await tester.tap(find.byTooltip(_pullTooltip));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip(_prTooltip));
    await tester.pump(const Duration(milliseconds: 50));

    // Assert
    expect(
      calls,
      {'pull': 1, 'pr': 1},
      reason: 'Mỗi nút phải nhận đúng click của nó. `vscode` xuất hiện ở đây = '
          'arena regression đã quay lại.',
    );
    expect(selectedCalls, isEmpty,
        reason: 'Click nút không được rơi xuống hàng và đổi tick.');
  });
}
