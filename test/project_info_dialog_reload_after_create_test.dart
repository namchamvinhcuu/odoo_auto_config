// Regression test cho bug: sau khi tạo database mới qua `CreateDbDialog`
// (nút "Tạo Database" trong `ProjectInfoDialog`), danh sách `_databases`
// (cache local, nạp 1 lần trong `initState`) KHÔNG refresh — phải đóng
// `ProjectInfoDialog` rồi mở lại mới thấy DB mới.
//
// Root cause: callback `onCreated` của `CreateDbDialog` (trong
// `_showCreateDbDialog()`) chỉ set `_dbNameController.text` + gọi
// `widget.onDbChanged(dbName)`, KHÔNG gọi lại `_loadDatabases()`.
// Fix: thêm `_loadDatabases();` vào cuối callback `onCreated`.
//
// `_loadDatabases()` gọi PostgresService.detectServers() (static, Process.run
// thật vào Docker/Postgres) — không có DI point sẵn để mock. Seam test-only
// `loadDatabasesOverride` (optional, mặc định null → hành vi production giữ
// nguyên) được thêm vào `ProjectInfoDialog` để test verify closure thật của
// `onCreated` (không phải bản sao/giả lập) có gọi `_loadDatabases()` hay
// không, mà không cần Docker/Postgres.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/models/project_info.dart';
import 'package:odoo_auto_config/screens/odoo_projects/create_db_dialog.dart';
import 'package:odoo_auto_config/screens/odoo_projects/project_info_dialog.dart';

void main() {
  const project = ProjectInfo(
    name: 'test_project',
    path: '/tmp/does-not-exist-test-project',
    description: '',
    httpPort: 8069,
    longpollingPort: 8072,
    createdAt: '2026-01-01',
  );

  Widget wrap({required Future<void> Function() loadDatabasesOverride}) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ProjectInfoDialog(
            project: project,
            onDbChanged: (_) {},
            onSaved: (_) async {},
            onNginxSetup: (_) async {},
            onNginxRemove: (_) async {},
            loadDatabasesOverride: loadDatabasesOverride,
          ),
        ),
      );

  testWidgets(
      'onCreated callback của CreateDbDialog gọi lại _loadDatabases '
      '(regression cho bug DB list không refresh sau khi tạo DB mới)',
      (tester) async {
    // Arrange
    var reloadCallCount = 0;
    await tester.pumpWidget(wrap(loadDatabasesOverride: () async {
      reloadCallCount++;
    }));
    await tester.pumpAndSettle();

    // initState() đã gọi _loadDatabases() 1 lần.
    expect(reloadCallCount, 1,
        reason: 'initState phải load database list 1 lần khi mở dialog');

    // Act: tap "Create Database" để mở CreateDbDialog, rồi gọi thẳng
    // callback `onCreated` thật (không phải bản giả lập) mà
    // `_showCreateDbDialog()` build ra — mô phỏng đúng lúc tạo DB xong.
    final createButton = find.widgetWithText(FilledButton, 'Create Database');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final createDbDialog = tester.widget<CreateDbDialog>(
      find.byType(CreateDbDialog),
    );
    createDbDialog.onCreated('new_db_created_by_user');
    await tester.pumpAndSettle();

    // Assert: onCreated phải trigger reload danh sách database.
    expect(reloadCallCount, 2,
        reason: 'onCreated phải gọi lại _loadDatabases() để danh sách '
            'database hiện đúng DB vừa tạo, không cần đóng/mở lại dialog');
  });
}
