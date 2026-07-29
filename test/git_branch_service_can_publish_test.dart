// Unit test cho `GitBranchService.canPublishBranch` — gate `publishable`
// ([[Architecture/Git-Status-Paths]] §Gate publishable).
//
// Vì sao predicate này được tách ra khỏi `loadBranchStatus`, và vì sao test
// PHẢI ở tầng này chứ không phải tầng provider:
//
//   Trong `loadBranchStatus`, rule `branch.isNotEmpty` KHÔNG có input nào phân
//   biệt được "gate còn" với "gate bị xoá": trạng thái duy nhất khiến
//   `branch == ''` là repo `git init` chưa có commit, mà ở đúng trạng thái đó
//   lệnh `rev-list --count HEAD --not --remotes` cũng rc=128 ⇒ hàm trả 0 dù gate
//   còn hay mất. Đó là ca thật của [[Knowledge-Base/Verification-Rules]] Rule 4
//   ("không test được trung thực" là kết luận hợp lệ) — và cách xử lý ưu tiên #1
//   của chính Rule 4 là ĐỔI THIẾT KẾ cho nó quan sát được, không phải viết test
//   tautology qua git fixture.
//
// Ở tầng predicate thuần này, mỗi rule có input phân biệt riêng ⇒ xoá bất kỳ
// rule nào cũng có test đỏ (đã đo bằng mutation, xem /tmp/git-tile-test-gaps-tests.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';

void main() {
  group('GitBranchService.canPublishBranch', () {
    test('branch ĐÃ có upstream → false (hành động đúng là Push, không Publish)',
        () {
      // Arrange + Act
      final result = GitBranchService.canPublishBranch(
        hasUpstream: true,
        branch: 'feature/x',
      );

      // Assert
      expect(
        result,
        isFalse,
        reason: 'Có upstream ⇒ Publish vô nghĩa; badge unpublished phải TẮT và '
            'nút hiện ra phải là Push.',
      );
    });

    test(
        'không upstream + branch RỖNG → false '
        '(rule branch.isNotEmpty — lý do gap tồn tại)', () {
      // Arrange + Act: `git init` chưa có commit nào → `rev-parse --abbrev-ref`
      // không trả tên branch ⇒ branch rỗng. Không có gì để publish, và
      // `HEAD --not --remotes` ở trạng thái đó sẽ đếm cả history.
      final result = GitBranchService.canPublishBranch(
        hasUpstream: false,
        branch: '',
      );

      // Assert
      expect(
        result,
        isFalse,
        reason: 'Đây chính là rule trước đây KHÔNG quan sát được ở tầng '
            'provider (unborn branch làm lệnh đếm cũng rc=128 → 0 dù gate còn '
            'hay mất). Ở tầng predicate nó phải phân biệt được.',
      );
    });

    test('không upstream + detached HEAD → false', () {
      // Arrange + Act: `push -u origin HEAD` bị git từ chối ("not a full
      // refname") ⇒ mời gọi Publish ở đây là mời một hành động bất khả thi.
      final result = GitBranchService.canPublishBranch(
        hasUpstream: false,
        branch: 'HEAD',
      );

      // Assert
      expect(result, isFalse);
    });

    test('không upstream + branch thường → true (đúng ca cần Publish)', () {
      // Arrange + Act: branch local thật, chưa từng push lên remote nào.
      final result = GitBranchService.canPublishBranch(
        hasUpstream: false,
        branch: 'feature/x',
      );

      // Assert
      expect(
        result,
        isTrue,
        reason: 'Ca duy nhất được phép đếm unpublished + hiện nút Publish. '
            'Nếu ca này false thì badge/nút biến mất hoàn toàn.',
      );
    });

    test('branch tên "HEADless" KHÔNG bị chặn oan (so sánh đúng bằng, không prefix)',
        () {
      // Arrange + Act: chốt rằng rule detached-HEAD dùng `!=` chứ không phải
      // startsWith/contains — branch hợp lệ có tiền tố "HEAD" vẫn publish được.
      final result = GitBranchService.canPublishBranch(
        hasUpstream: false,
        branch: 'HEADless',
      );

      // Assert
      expect(result, isTrue);
    });
  });
}
