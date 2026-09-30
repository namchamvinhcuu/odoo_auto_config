// Test cho `SelectivePullLogDialog` sau khi đổi constructor sang
// `(title, repos: List<({String name, String path})>)` — phục vụ nút
// "Pull all" ở màn Other Projects (task `other-projects-pull-all`) và vẫn là
// dialog của Selective Pull (Odoo projects).
//
// Điểm cần bảo vệ:
//   1. `git pull` chạy trong ĐÚNG `path` của từng entry (không còn ghép
//      `<projectPath>/addons/<repo>`) → file mới từ remote xuất hiện thật.
//   2. Log báo kết quả THẬT theo exit code: `[+] <name> done` /
//      `[-] <name> failed (exit N)`, một repo lỗi không chặn repo sau, cuối
//      cùng luôn `[+] Done!`.
//   3. Nhiều entry trùng `name` (Other Projects có thể trùng tên folder ở
//      2 thư mục khác nhau) vẫn chạy đủ từng entry — lặp theo list, không
//      dedupe theo name.
//
// Dialog gọi `startGit` (Process.start) trực tiếp → git fixture THẬT +
// `tester.runAsync`; không dùng pumpAndSettle (LinearProgressIndicator vô hạn).
// Xem ghi chú kỹ thuật ở test/git_branch_dialog_push_button_test.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/l10n/app_localizations.dart';
import 'package:odoo_auto_config/screens/odoo_projects/selective_pull_log_dialog.dart';
import 'package:path/path.dart' as p;

Future<void> _git(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
}

Future<void> _configIdentity(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
  await _git(['config', 'pull.rebase', 'false'], cwd);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('selective_pull_log_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Dựng bare remote `<dir>/remote.git` + clone `<dir>/local` BEHIND 1 commit
  /// (commit `remote-new.txt` được push từ clone thứ hai). Trả path clone behind.
  Future<String> makeBehindRepo(String dir) async {
    final remote = p.join(dir, 'remote.git');
    final local = p.join(dir, 'local');
    final other = p.join(dir, 'other');
    Directory(remote).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remote], dir);
    await _git(['clone', remote, local], dir);
    await _configIdentity(local);
    File(p.join(local, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], local);
    await _git(['commit', '-m', 'initial'], local);
    await _git(['push', '-u', 'origin', 'main'], local);

    await _git(['clone', remote, other], dir);
    await _configIdentity(other);
    File(p.join(other, 'remote-new.txt')).writeAsStringSync('new\n');
    await _git(['add', '.'], other);
    await _git(['commit', '-m', 'remote change'], other);
    await _git(['push'], other);
    return local;
  }

  Widget wrap(String title, List<({String name, String path})> repos) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SelectivePullLogDialog(title: title, repos: repos),
        ),
      );

  /// Mount dialog + chờ vòng pull kết thúc (progress bar biến mất).
  Future<void> mountAndRun(
    WidgetTester tester,
    Future<List<({String name, String path})>> Function() buildRepos, {
    String title = 'Pull all (N)',
  }) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      final repos = await buildRepos();
      await tester.pumpWidget(wrap(title, repos));
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
      }
      fail('SelectivePullLogDialog chưa kết thúc sau ~10s.');
    });
  }

  Finder logLine(String s) => find.textContaining(s, findRichText: true);

  testWidgets(
      'pull trong đúng path từng entry: repo behind → done + file mới xuất '
      'hiện; path không phải repo → failed (exit N); vẫn chạy tiếp + Done!',
      (tester) async {
    // Arrange
    late String behind;
    final notRepo = p.join(tmp.path, 'not_a_repo');

    // Act
    await mountAndRun(tester, () async {
      behind = await makeBehindRepo(p.join(tmp.path, 'a'));
      Directory(notRepo).createSync(recursive: true);
      // Repo lỗi đặt TRƯỚC → chứng minh lỗi không chặn repo sau.
      return [
        (name: 'broken', path: notRepo),
        (name: 'alpha', path: behind),
      ];
    }, title: 'Pull all projects (2)');

    // Assert: title truyền vào được hiển thị nguyên văn.
    expect(find.text('Pull all projects (2)'), findsOneWidget);
    // Log kết quả theo exit code thật.
    expect(logLine('> git pull (broken)'), findsOneWidget);
    expect(logLine('[-] broken failed (exit '), findsOneWidget);
    expect(logLine('> git pull (alpha)'), findsOneWidget);
    expect(logLine('[+] alpha done'), findsOneWidget);
    expect(logLine('[-] alpha failed'), findsNothing);
    expect(logLine('[+] Done!'), findsOneWidget);
    // Pull thật sự chạy trong `path` → file từ remote đã về working tree.
    expect(File(p.join(behind, 'remote-new.txt')).existsSync(), isTrue,
        reason: 'git pull phải chạy trong path của entry, không ghép addons/');
  });

  testWidgets(
      'nhiều entry trùng name ở path khác nhau → chạy đủ từng entry, '
      'không dedupe theo name', (tester) async {
    // Arrange
    late String first;
    late String second;

    // Act
    await mountAndRun(tester, () async {
      first = await makeBehindRepo(p.join(tmp.path, 'x'));
      second = await makeBehindRepo(p.join(tmp.path, 'y'));
      return [
        (name: 'same', path: first),
        (name: 'same', path: second),
      ];
    });

    // Assert
    expect(logLine('> git pull (same)'), findsNWidgets(2));
    expect(logLine('[+] same done'), findsNWidgets(2));
    expect(logLine('[+] Done!'), findsOneWidget);
    expect(File(p.join(first, 'remote-new.txt')).existsSync(), isTrue);
    expect(File(p.join(second, 'remote-new.txt')).existsSync(), isTrue);
  });

  testWidgets('list rỗng → không chạy git, vẫn in Done! và tắt progress',
      (tester) async {
    // Act
    await mountAndRun(tester, () async => const []);

    // Assert
    expect(logLine('> git pull'), findsNothing);
    expect(logLine('[+] Done!'), findsOneWidget);
  });
}
