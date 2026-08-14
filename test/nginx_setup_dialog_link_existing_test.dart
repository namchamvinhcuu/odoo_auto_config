// Test cho `NginxSetupDialog` — section "Link existing Nginx".
//
// Bug đã fix: khi `existingSubdomains` có nhiều item, section này từng render
// trực tiếp bằng `.map()` vào một `Column` không giới hạn chiều cao → dialog
// phình quá màn hình, nút "Setup Nginx" bị đè lên danh sách (RenderFlex
// overflow). Fix: bọc trong `Container(height: AppDialog.listHeight, ...)` +
// `ListView.builder` (scroll nội bộ, xem lib/widgets/nginx_setup_dialog.dart).
//
// Test cover:
// 1. Nhiều item (20) → không overflow, danh sách nằm trong vùng scroll giới
//    hạn chiều cao (không render hết cả 20 ListTile cùng lúc).
// 2. Tap 1 item → dialog pop đúng `(subdomain, port: null, isLink: true)`.
// 3. `existingSubdomains` rỗng → KHÔNG hiển thị section (regression guard).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/widgets/nginx_setup_dialog.dart';

void main() {
  NginxSetupResult? capturedResult;
  bool resultCaptured = false;

  Widget wrap({required Set<String> existingSubdomains}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showDialog<NginxSetupResult>(
                  context: context,
                  builder: (_) => NginxSetupDialog(
                    initialSubdomain: 'myproject',
                    domainSuffix: '.example.com',
                    existingSubdomains: existingSubdomains,
                  ),
                );
                capturedResult = result;
                resultCaptured = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

  setUp(() {
    capturedResult = null;
    resultCaptured = false;
  });

  testWidgets(
      'existingSubdomains có 20 item → dialog render không overflow, '
      'danh sách nằm trong vùng scroll giới hạn chiều cao', (tester) async {
    // Arrange
    final many = {for (var i = 0; i < 20; i++) 'sub$i'};

    // Act
    await tester.pumpWidget(wrap(existingSubdomains: many));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Assert: render xong không có exception (RenderFlex overflowed by...
    // là bug cũ khi Column render thẳng 20 ListTile không giới hạn chiều cao).
    expect(tester.takeException(), isNull,
        reason:
            '20 item trong "Link existing" không được làm dialog overflow.');

    expect(find.byType(ListView), findsOneWidget,
        reason: 'Danh sách phải dùng ListView.builder (scroll nội bộ), '
            'không phải Column .map() không giới hạn chiều cao.');
    // ListView.builder chỉ build item nằm trong viewport (~150px cao,
    // mỗi ListTile dense cao hơn nhiều) → không thể render đủ cả 20 item
    // cùng lúc nếu danh sách thực sự bị giới hạn chiều cao.
    expect(find.byType(ListTile).evaluate().length, lessThan(20),
        reason: 'Vùng danh sách phải bị giới hạn chiều cao (viewport hẹp '
            'hơn tổng chiều cao 20 item), không phải render tất cả.');
  });

  testWidgets(
      'tap 1 item trong "Link existing" → dialog pop với '
      '(subdomain: <tên>, port: null, isLink: true)', (tester) async {
    // Arrange
    await tester.pumpWidget(
      wrap(existingSubdomains: {'alpha', 'beta', 'gamma'}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Act: tap item "beta" (Text hiển thị đúng bằng tên subdomain, không
    // trùng với subtitle "beta.example.com").
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();

    // Assert
    expect(resultCaptured, isTrue,
        reason: 'Navigator.pop phải trả kết quả về showDialog caller.');
    expect(capturedResult, isNotNull);
    expect(capturedResult!.subdomain, 'beta');
    expect(capturedResult!.port, isNull);
    expect(capturedResult!.isLink, isTrue);
  });

  testWidgets(
      'existingSubdomains rỗng → KHÔNG hiển thị section "Link existing '
      'Nginx" (regression guard, giữ hành vi cũ)', (tester) async {
    // Arrange + Act
    await tester.pumpWidget(wrap(existingSubdomains: {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Link existing Nginx'), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });
}
