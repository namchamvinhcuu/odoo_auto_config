// Test cho `RepoInfo.applyDivergence` — nơi ghi ahead/behind/hasUpstream của
// đường Odoo Workspace.
//
// Vì sao tách ra method public để test: 3 dòng gán này trước đây nằm trong
// `_OdooWorkspaceDialogState._computeAheadBehind` (private, phải mount dialog
// ~1400 dòng mới chạm tới) nên mutation **M9 vòng 4** — swap `aheadCount` ↔
// `behindCount` — KHÔNG có test nào bắt. File này đóng đúng khoảng trống đó,
// unit test thuần: không git, không Process, không widget.
//
// Contract cần khoá: ghi **CẢ BỐN** field, ghi **vô điều kiện**. `RepoInfo` là
// object mutable được reuse giữa các lần refresh, nên cập nhật một phần =
// badge giữ số của branch trước (đúng bug 🟠 gốc của task này).
//
// Field thứ 4 (`unpublishedCount`) được thêm ở đợt 3 và là tham số **required**
// có chủ đích: nó thuộc CÙNG một lần reset. Branch vừa được publish (gained
// upstream) thì không còn gì "chưa publish" — caller cập nhật divergence mà quên
// xoá số này sẽ để badge/nút Publish sống sót trên branch giờ cần Push. Đúng họ
// clobber-bug mà [[Architecture/Git-Status-Paths]] đã ghi 4 lần.

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/repo_info.dart';

void main() {
  RepoInfo makeRepo() => RepoInfo(name: 'addon_x', path: '/tmp/addon_x');

  test('applyDivergence ghi đúng từng field (ahead != behind → phát hiện swap)',
      () async {
    // Arrange: 3 số KHÁC NHAU ĐÔI MỘT — nếu 2 dòng gán nào bị đảo thì test đỏ.
    final repo = makeRepo();

    // Act
    repo.applyDivergence(
      (ahead: 1, behind: 2, hasUpstream: true),
      unpublishedCount: 9,
    );

    // Assert
    expect(repo.aheadCount, 1, reason: 'ahead phải vào aheadCount.');
    expect(repo.behindCount, 2, reason: 'behind phải vào behindCount.');
    expect(repo.hasUpstream, isTrue);
    expect(repo.unpublishedCount, 9,
        reason: 'Tham số required phải được GHI, không chỉ được nhận.');
  });

  test(
      'applyDivergence lần 2 XOÁ SẠCH số của lần 1 khi mất upstream '
      '(regression: stale ahead/behind badge — finding 🟠)', () async {
    // Arrange: lần refresh trước đo được ahead 5 / behind 7 (badge đang hiện).
    final repo = makeRepo();
    repo.applyDivergence(
      (ahead: 5, behind: 7, hasUpstream: true),
      unpublishedCount: 0,
    );
    expect(repo.aheadCount, 5, reason: 'Pre-condition: badge đang hiện 5.');
    expect(repo.behindCount, 7, reason: 'Pre-condition: badge đang hiện 7.');

    // Act: user switch sang branch chưa publish → helper trả (0, 0, false).
    repo.applyDivergence(
      (ahead: 0, behind: 0, hasUpstream: false),
      unpublishedCount: 0,
    );

    // Assert: cả 3 field phải bị ghi đè — RepoInfo được reuse nên bỏ sót field
    // nào là field đó giữ giá trị branch cũ và badge stale.
    expect(repo.aheadCount, 0,
        reason: 'Không có upstream → không có commit chưa push → badge tắt.');
    expect(repo.behindCount, 0,
        reason: 'Không có upstream → không thể behind → badge tắt.');
    expect(repo.hasUpstream, isFalse,
        reason: 'Cờ này quyết định hiện Push hay Publish; bỏ sót là sai hẳn '
            'affordance.');
  });

  test('applyDivergence phục hồi khi branch có upstream trở lại '
      '(hasUpstream không được "kẹt" false)', () async {
    // Arrange: đang ở trạng thái không upstream (vd branch mới chưa publish).
    final repo = makeRepo();
    repo.applyDivergence(
      (ahead: 0, behind: 0, hasUpstream: false),
      unpublishedCount: 0,
    );

    // Act: user publish branch → lần đo sau có upstream + 3 commit chưa push.
    repo.applyDivergence(
      (ahead: 3, behind: 4, hasUpstream: true),
      unpublishedCount: 0,
    );

    // Assert: chiều ngược lại cũng phải cập nhật đủ.
    expect(repo.aheadCount, 3);
    expect(repo.behindCount, 4);
    expect(repo.hasUpstream, isTrue);
  });

  test(
      'unpublishedCount của lần trước KHÔNG sống sót khi branch vừa được publish '
      '(regression: badge/nút Publish kẹt trên branch giờ cần Push)', () async {
    // Arrange: lần đo trước — branch chưa publish, 5 commit local ⇒ badge
    // "5 chưa publish" + nút Publish đang hiện trên tile.
    final repo = makeRepo();
    repo.applyDivergence(
      (ahead: 0, behind: 0, hasUpstream: false),
      unpublishedCount: 5,
    );
    expect(repo.unpublishedCount, 5,
        reason: 'Pre-condition: badge đang hiện 5 commit chưa publish.');

    // Act: user bấm Publish → phase 2 đo lại: branch giờ CÓ upstream, và
    // `loadPublishableCount` trả 0 vì gate `!hasUpstream` chặn.
    repo.applyDivergence(
      (ahead: 0, behind: 0, hasUpstream: true),
      unpublishedCount: 0,
    );

    // Assert: số của lần TRƯỚC phải bị ghi đè, không được "còn sống".
    expect(
      repo.unpublishedCount,
      0,
      reason: 'RepoInfo là object mutable reuse giữa các lần refresh. Bỏ dòng '
          'gán này ⇒ tile vẫn hiện badge 5 + nút Publish trên branch đã có '
          'upstream (nút Publish chỉ hiện khi `!hasUpstream`, nên user thấy '
          'badge "5 chưa publish" cạnh nút Push — sai hẳn trạng thái).',
    );
    expect(repo.hasUpstream, isTrue);
  });
}
