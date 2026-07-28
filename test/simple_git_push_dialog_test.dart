// Test cho `SimpleGitPushDialog` — dialog push trực tiếp từ card project
// (phần thứ hai của yêu cầu `push-btn-ahead-detect`: push được mà không cần mở
// dialog Git Branches).
//
// Điểm cần bảo vệ: dialog phải BÁO KẾT QUẢ THẬT theo exit code của `git push`
// (thành công → "Pushed!", thất bại → "Push failed with exit code N") và không
// im lặng nuốt lỗi từ stderr.
//
// Dialog gọi `Process.start` trực tiếp (không inject được) → dùng git fixture
// THẬT + `tester.runAsync`. Xem ghi chú kỹ thuật đầy đủ ở đầu
// test/git_branch_dialog_push_button_test.dart (fake-async không resolve I/O
// thật; không dùng pumpAndSettle vì có LinearProgressIndicator vô hạn).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/screens/other_projects/simple_git_push_dialog.dart';
import 'package:path/path.dart' as p;

/// Chạy 1 lệnh git trong [cwd], fail test nếu exitCode != 0.
Future<void> _git(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
}

void main() {
  late Directory tmp;
  late String remotePath;
  late String localPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('simple_git_push_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(String path) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: const TextScaler.linear(0.7),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SimpleGitPushDialog(
            projectName: 'fixture',
            projectPath: path,
          ),
        ),
      );

  /// Dựng fixture (bare remote + clone đã push "initial") + [aheadCommits]
  /// commit local chưa push; [detachUpstream] để mô phỏng branch chưa publish.
  /// Mount dialog rồi chờ `git push` chạy xong (LinearProgressIndicator tắt).
  Future<void> mountAndRunPush(
    WidgetTester tester, {
    int aheadCommits = 1,
    bool noUpstream = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      Directory(remotePath).createSync(recursive: true);
      await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);
      await _git(['clone', remotePath, localPath], tmp.path);
      await _git(['config', 'user.email', 'test@example.com'], localPath);
      await _git(['config', 'user.name', 'Test'], localPath);
      await _git(['config', 'commit.gpgsign', 'false'], localPath);
      // Pin để deterministic: với `push.autoSetupRemote=true` (config global của
      // một số máy) push trên branch chưa có upstream sẽ TỰ tạo upstream.
      await _git(['config', 'push.default', 'simple'], localPath);
      await _git(['config', 'push.autoSetupRemote', 'false'], localPath);
      File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
      await _git(['add', '.'], localPath);
      await _git(['commit', '-m', 'initial'], localPath);
      await _git(['push', '-u', 'origin', 'main'], localPath);

      if (noUpstream) {
        await _git(['checkout', '-b', 'orphan'], localPath);
      }
      for (var i = 0; i < aheadCommits; i++) {
        File(p.join(localPath, 'local-$i.txt')).writeAsStringSync('c$i\n');
        await _git(['add', '.'], localPath);
        await _git(['commit', '-m', 'local-only-$i'], localPath);
      }

      await tester.pumpWidget(wrap(localPath));

      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
      }
      fail('SimpleGitPushDialog chưa kết thúc sau ~5s.');
    });
  }

  /// Số commit local chưa push của branch hiện tại trong [cwd].
  Future<int> aheadOf(String cwd) async {
    final r = await Process.run(
      'git',
      ['rev-list', '--count', '@{upstream}..HEAD'],
      workingDirectory: cwd,
    );
    return int.tryParse((r.stdout as String).trim()) ?? -1;
  }

  testWidgets('push thành công → log báo "Pushed!" và remote nhận commit',
      (tester) async {
    // Arrange + Act
    await mountAndRunPush(tester, aheadCommits: 1);

    // Assert: (1) UI báo thành công...
    expect(
      find.textContaining('Pushed!', findRichText: true),
      findsOneWidget,
      reason: 'exit 0 → phải in dòng thành công cho user thấy.',
    );
    // ...(2) và commit thật sự lên remote (không chỉ in chữ cho đẹp).
    int? ahead;
    await tester.runAsync(() async => ahead = await aheadOf(localPath));
    expect(ahead, 0,
        reason: 'Sau push, branch không còn commit nào chưa push.');
  });

  testWidgets('push thất bại (branch chưa có upstream) → log báo exit code, '
      'không im lặng', (tester) async {
    // Arrange + Act: branch `orphan` chưa publish → `git push` fatal.
    await mountAndRunPush(tester, aheadCommits: 1, noUpstream: true);

    // Assert: dòng lỗi có mã exit → user biết push KHÔNG thành công.
    expect(
      find.textContaining('Push failed with exit code', findRichText: true),
      findsOneWidget,
      reason: 'exit != 0 → phải báo lỗi; nếu chỉ đọc stdout thì dialog trông '
          'như đã push xong.',
    );
    expect(find.textContaining('Pushed!', findRichText: true), findsNothing);
  });
}
