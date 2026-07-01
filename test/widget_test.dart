import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/main.dart';
import 'package:odoo_auto_config/providers/docker_status_provider.dart';
import 'package:odoo_auto_config/providers/update_provider.dart';

/// No-op override: build() KHÔNG fire IO (Process.run docker / Future.delayed
/// retry loop) → tránh "Timer still pending" trong test env, giữ nguyên state
/// mặc định để HomeScreen render bình thường.
class _FakeDockerStatusNotifier extends DockerStatusNotifier {
  @override
  DockerStatus build() => const DockerStatus();
}

/// No-op override: build() KHÔNG fire network check-for-update.
class _FakeUpdateNotifier extends UpdateNotifier {
  @override
  UpdateState build() => const UpdateState();
}

void main() {
  testWidgets('App builds MaterialApp without crashing', (
    WidgetTester tester,
  ) async {
    // Arrange: desktop app render ở màn hình rộng. Viewport test mặc định
    // (800x600) quá nhỏ → HomeScreen layout tràn. Set size desktop để render
    // không overflow, khớp môi trường chạy thật.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // OdooAutoConfigApp là ConsumerWidget → cần ProviderScope ancestor.
    // Override provider IO-heavy (docker poll + update check) bằng no-op để
    // test deterministic, KHÔNG gọi Process.run/network thật.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dockerStatusProvider.overrideWith(_FakeDockerStatusNotifier.new),
          updateProvider.overrideWith(_FakeUpdateNotifier.new),
        ],
        child: const OdooAutoConfigApp(),
      ),
    );

    // Act: pump 1 frame. KHÔNG pumpAndSettle — HomeScreen còn provider async
    // khác có thể chạy nền; pumpAndSettle dễ treo/flaky trên desktop app.
    await tester.pump();

    // Assert: cây widget dựng ra đúng 1 MaterialApp (smoke test — render OK).
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
