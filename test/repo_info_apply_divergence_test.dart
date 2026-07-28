// Test cho `RepoInfo.applyDivergence` — nơi ghi ahead/behind/hasUpstream của
// đường Odoo Workspace.
//
// Vì sao tách ra method public để test: 3 dòng gán này trước đây nằm trong
// `_OdooWorkspaceDialogState._computeAheadBehind` (private, phải mount dialog
// ~1400 dòng mới chạm tới) nên mutation **M9 vòng 4** — swap `aheadCount` ↔
// `behindCount` — KHÔNG có test nào bắt. File này đóng đúng khoảng trống đó,
// unit test thuần: không git, không Process, không widget.
//
// Contract cần khoá: ghi **CẢ BA** field, ghi **vô điều kiện**. `RepoInfo` là
// object mutable được reuse giữa các lần refresh, nên cập nhật một phần =
// badge giữ số của branch trước (đúng bug 🟠 gốc của task này).

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/screens/odoo_workspace/repo_info.dart';

void main() {
  RepoInfo makeRepo() => RepoInfo(name: 'addon_x', path: '/tmp/addon_x');

  test('applyDivergence ghi đúng từng field (ahead != behind → phát hiện swap)',
      () async {
    // Arrange: 2 số KHÁC NHAU — nếu 2 dòng gán bị đảo thì test đỏ.
    final repo = makeRepo();

    // Act
    repo.applyDivergence((ahead: 1, behind: 2, hasUpstream: true));

    // Assert
    expect(repo.aheadCount, 1, reason: 'ahead phải vào aheadCount.');
    expect(repo.behindCount, 2, reason: 'behind phải vào behindCount.');
    expect(repo.hasUpstream, isTrue);
  });

  test(
      'applyDivergence lần 2 XOÁ SẠCH số của lần 1 khi mất upstream '
      '(regression: stale ahead/behind badge — finding 🟠)', () async {
    // Arrange: lần refresh trước đo được ahead 5 / behind 7 (badge đang hiện).
    final repo = makeRepo();
    repo.applyDivergence((ahead: 5, behind: 7, hasUpstream: true));
    expect(repo.aheadCount, 5, reason: 'Pre-condition: badge đang hiện 5.');
    expect(repo.behindCount, 7, reason: 'Pre-condition: badge đang hiện 7.');

    // Act: user switch sang branch chưa publish → helper trả (0, 0, false).
    repo.applyDivergence((ahead: 0, behind: 0, hasUpstream: false));

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
    repo.applyDivergence((ahead: 0, behind: 0, hasUpstream: false));

    // Act: user publish branch → lần đo sau có upstream + 3 commit chưa push.
    repo.applyDivergence((ahead: 3, behind: 4, hasUpstream: true));

    // Assert: chiều ngược lại cũng phải cập nhật đủ.
    expect(repo.aheadCount, 3);
    expect(repo.behindCount, 4);
    expect(repo.hasUpstream, isTrue);
  });
}
