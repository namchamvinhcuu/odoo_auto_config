// Unit test THUẦN cho `hasPendingGitWork` (top-level function trong
// `lib/screens/other_projects/other_projects_screen.dart`) — bộ lọc "project
// có git change hoặc đã commit nhưng chưa push" trên màn Other Projects.
//
// ── Vì sao test thuần, không widget ──
// `hasPendingGitWork` được tách từ method private `_hasPendingGitWork` của
// `_OtherProjectsScreenState` thành hàm top-level ĐÚNG để test được không cần
// dựng `OtherProjectsScreen` thật — dựng screen thật sẽ chạm
// `StorageService.loadSettings`/`updateSettings`, ghi THẬT vào
// `~/.config/odoo_auto_config/odoo_auto_config.json` trên máy đang chạy test
// (không có injection point để override HOME giữa chừng process Dart) — vi
// phạm test isolation. Hàm top-level chỉ đọc 3 map trên `OtherProjectsState`
// nên không chạm I/O gì cả.
//
// Logic: OR của 3 điều kiện — có file thay đổi CHƯA commit (`changedCount`),
// có commit local CHƯA push lên upstream đã tồn tại (`aheadCount`), hoặc có
// commit trên nhánh CHƯA từng publish lên remote (`unpublishedCount`).

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/models/workspace_info.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';
import 'package:odoo_auto_config/screens/other_projects/other_projects_screen.dart';

void main() {
  final ws = WorkspaceInfo(
    name: 'proj_a',
    path: '/fixture/proj_a',
    type: 'Odoo',
    description: '',
    createdAt: '2026-07-29',
  );

  test('changedCount>0 (các map khác rỗng) → true', () {
    final state = OtherProjectsState(
      workspaces: [ws],
      changedCount: {ws.path: 2},
    );

    expect(hasPendingGitWork(ws, state), true,
        reason: 'Có file thay đổi chưa commit ⇒ phải tính là pending.');
  });

  test('aheadCount>0 (các map khác rỗng) → true', () {
    final state = OtherProjectsState(
      workspaces: [ws],
      aheadCount: {ws.path: 1},
    );

    expect(hasPendingGitWork(ws, state), true,
        reason: 'Có commit local chưa push lên upstream đã tồn tại ⇒ pending.');
  });

  test('unpublishedCount>0 (các map khác rỗng) → true', () {
    final state = OtherProjectsState(
      workspaces: [ws],
      unpublishedCount: {ws.path: 3},
    );

    expect(hasPendingGitWork(ws, state), true,
        reason: 'Nhánh chưa từng publish nhưng có commit ⇒ pending.');
  });

  test('cả 3 map đều 0/rỗng cho path này → false', () {
    final state = OtherProjectsState(
      workspaces: [ws],
      changedCount: {ws.path: 0},
      aheadCount: {ws.path: 0},
      unpublishedCount: {ws.path: 0},
    );

    expect(hasPendingGitWork(ws, state), false,
        reason: 'Không có việc gì cần push/publish/commit ⇒ KHÔNG pending.');
  });

  test('path hoàn toàn vắng mặt trong cả 3 map (chưa từng loadBranchStatus) '
      '→ false (đọc `?? 0`, không throw)', () {
    // Regression-shape: state rỗng hoàn toàn cho path này — mô phỏng lúc
    // workspace vừa thêm, `loadBranches` nền chưa kịp chạy xong.
    final state = OtherProjectsState(workspaces: [ws]);

    expect(hasPendingGitWork(ws, state), false);
  });

  test('map có dữ liệu của path KHÁC, không phải path đang xét → false', () {
    // Bắt lỗi keo nhầm path (vd luôn đọc index 0 thay vì key theo path).
    final other = WorkspaceInfo(
      name: 'proj_b',
      path: '/fixture/proj_b',
      type: 'Odoo',
      description: '',
      createdAt: '2026-07-29',
    );
    final state = OtherProjectsState(
      workspaces: [ws, other],
      changedCount: {other.path: 5},
      aheadCount: {other.path: 2},
      unpublishedCount: {other.path: 1},
    );

    expect(hasPendingGitWork(ws, state), false,
        reason: 'Dữ liệu pending thuộc về proj_b, không phải proj_a (ws).');
  });
}
