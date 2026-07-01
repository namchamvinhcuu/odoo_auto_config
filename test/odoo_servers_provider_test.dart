// Unit test cho logic thuần trong odoo_servers_provider.dart:
//   - isOdooHttpReadyLine(String): nhận diện dòng log "HTTP running" của Odoo
//     để auto-mở browser khi server ready.
//   - OdooServerState.copyWith / isActive: immutable snapshot của server.
//
// Không test RunningServersNotifier.launch/start/killTree (spawn process thật,
// cross-platform → integration/manual). Chỉ cover pure logic ở đây.

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/providers/odoo_servers_provider.dart';

void main() {
  group('isOdooHttpReadyLine', () {
    test('dòng werkzeug 0.0.0.0:8069 → true', () {
      // Arrange
      const line =
          '2026-07-01 10:00:00,000 12345 INFO db odoo.service.server: HTTP service (werkzeug) running on 0.0.0.0:8069';

      // Act & Assert
      expect(isOdooHttpReadyLine(line), isTrue);
    });

    test('dòng running on 127.0.0.1:8069 → true', () {
      // Arrange
      const line = 'HTTP service running on 127.0.0.1:8069';

      // Act & Assert
      expect(isOdooHttpReadyLine(line), isTrue);
    });

    test('case-insensitive: chữ HOA vẫn nhận diện → true', () {
      // Arrange
      const line = 'ODOO.SERVICE.SERVER: HTTP SERVICE (WERKZEUG) RUNNING ON 0.0.0.0:8069';

      // Act & Assert
      expect(isOdooHttpReadyLine(line), isTrue);
    });

    test('dòng log thường (loading module) → false', () {
      // Arrange
      const line =
          '2026-07-01 10:00:00,000 12345 INFO db odoo.modules.loading: loading module base';

      // Act & Assert
      expect(isOdooHttpReadyLine(line), isFalse);
    });

    test('chuỗi rỗng → false', () {
      // Arrange
      const line = '';

      // Act & Assert
      expect(isOdooHttpReadyLine(line), isFalse);
    });
  });

  group('OdooServerState.isActive', () {
    test('starting → isActive true', () {
      // Arrange
      const state = OdooServerState(status: OdooServerStatus.starting);

      // Act & Assert
      expect(state.isActive, isTrue);
    });

    test('ready → isActive true', () {
      // Arrange
      const state = OdooServerState(status: OdooServerStatus.ready);

      // Act & Assert
      expect(state.isActive, isTrue);
    });

    test('idle (default) → isActive false', () {
      // Arrange
      const state = OdooServerState();

      // Act & Assert
      expect(state.status, OdooServerStatus.idle);
      expect(state.isActive, isFalse);
    });

    test('stopped → isActive false', () {
      // Arrange
      const state = OdooServerState(status: OdooServerStatus.stopped);

      // Act & Assert
      expect(state.isActive, isFalse);
    });

    test('error → isActive false', () {
      // Arrange
      const state = OdooServerState(status: OdooServerStatus.error);

      // Act & Assert
      expect(state.isActive, isFalse);
    });
  });

  group('OdooServerState.copyWith', () {
    test('không truyền field nào → giữ nguyên tất cả', () {
      // Arrange
      const original = OdooServerState(
        status: OdooServerStatus.ready,
        logs: ['a', 'b'],
        pid: 42,
      );

      // Act
      final copy = original.copyWith();

      // Assert
      expect(copy.status, OdooServerStatus.ready);
      expect(copy.logs, ['a', 'b']);
      expect(copy.pid, 42);
    });

    test('đổi status → giữ logs + pid cũ', () {
      // Arrange
      const original = OdooServerState(
        status: OdooServerStatus.starting,
        logs: ['x'],
        pid: 100,
      );

      // Act
      final copy = original.copyWith(status: OdooServerStatus.ready);

      // Assert
      expect(copy.status, OdooServerStatus.ready);
      expect(copy.logs, ['x']);
      expect(copy.pid, 100);
    });

    test('đổi logs → giữ status + pid cũ', () {
      // Arrange
      const original = OdooServerState(
        status: OdooServerStatus.ready,
        logs: ['old'],
        pid: 7,
      );

      // Act
      final copy = original.copyWith(logs: ['new1', 'new2']);

      // Assert
      expect(copy.logs, ['new1', 'new2']);
      expect(copy.status, OdooServerStatus.ready);
      expect(copy.pid, 7);
    });

    test('set pid mới qua closure', () {
      // Arrange
      const original = OdooServerState(pid: 1);

      // Act
      final copy = original.copyWith(pid: () => 999);

      // Assert
      expect(copy.pid, 999);
    });

    test('set pid = null qua closure trả null', () {
      // Arrange
      const original = OdooServerState(
        status: OdooServerStatus.stopped,
        pid: 500,
      );

      // Act: closure trả null → pid phải thành null (không giữ giá trị cũ).
      final copy = original.copyWith(pid: () => null);

      // Assert
      expect(copy.pid, isNull);
      expect(copy.status, OdooServerStatus.stopped);
    });

    test('pid closure null (không truyền) → giữ pid cũ, không clear', () {
      // Arrange
      const original = OdooServerState(pid: 321);

      // Act: không truyền pid closure → giữ nguyên.
      final copy = original.copyWith(status: OdooServerStatus.ready);

      // Assert
      expect(copy.pid, 321);
    });
  });
}
