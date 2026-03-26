import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OdooAutoConfigApp());
    expect(find.text('Odoo Auto Config'), findsOneWidget);
  });
}
