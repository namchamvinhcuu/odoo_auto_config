// Test hành vi cho phần THAY ĐỔI của `runGit`/`startGit`/
// `startGitInCurrentDir` (lib/services/git_process.dart): tham số
// `executable` đổi từ `String executable = 'git'` (literal PATH-dependent)
// sang `String? executable` — khi không truyền, giờ resolve
// `GitService.gitPath` (đã verify chạy được) thay vì bare `'git'`.
//
// Không mock: dùng `GitService.debugOverrideCachedGitPath` (seam test-only,
// KHÔNG đổi public API của gitPath/runGit/startGit/startGitInCurrentDir) để
// ép `GitService.gitPath` trỏ vào một chương trình IN RA ENV (`env` trên
// POSIX, `cmd /c set` trên Windows — cùng fixture ý tưởng với
// git_process_env_test.dart), rồi đọc stdout thật. Nếu 3 hàm này còn hardcode
// literal `'git'`, chúng sẽ chạy git thật với args của dumper (`[]` hoặc
// `['/c','set']`) — git không hiểu args đó, in usage ra STDERR, KHÔNG in
// "PATH=" ra stdout ⇒ test phân biệt được ngay, không cần mock.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_process.dart';
import 'package:odoo_auto_config/services/git_service.dart';

/// Chương trình in ra toàn bộ biến môi trường, theo OS — giống fixture của
/// git_process_env_test.dart.
({String exe, List<String> args}) get _envDumper => Platform.isWindows
    ? (exe: 'cmd', args: ['/c', 'set'])
    : (exe: 'env', args: <String>[]);

bool _looksLikeEnvDump(String out) => out.toLowerCase().contains('path=');

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('git_process_fallback_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    GitService.debugOverrideCachedGitPath(null);
  });

  group('KHÔNG truyền executable → resolve GitService.gitPath (không còn '
      'hardcode literal "git")', () {
    test('runGit chạy đúng chương trình mà GitService.gitPath trả về',
        () async {
      // Arrange — ép gitPath trỏ vào env-dumper thay vì git thật.
      final dumper = _envDumper;
      GitService.debugOverrideCachedGitPath(dumper.exe);

      // Act
      final result = await runGit(dumper.args, workingDir: tmp.path);

      // Assert
      expect(_looksLikeEnvDump(result.stdout as String), isTrue,
          reason: 'runGit phải resolve GitService.gitPath khi executable '
              'không được truyền — nếu vẫn hardcode literal "git", output '
              'này sẽ là usage text của git thật, không phải env dump');
    });

    test('startGit chạy đúng chương trình mà GitService.gitPath trả về',
        () async {
      // Arrange
      final dumper = _envDumper;
      GitService.debugOverrideCachedGitPath(dumper.exe);

      // Act
      final process = await startGit(dumper.args, workingDir: tmp.path);
      final out = await process.stdout.transform(systemEncoding.decoder).join();
      await process.exitCode;

      // Assert
      expect(_looksLikeEnvDump(out), isTrue);
    });

    test(
        'startGitInCurrentDir chạy đúng chương trình mà GitService.gitPath '
        'trả về', () async {
      // Arrange
      final dumper = _envDumper;
      GitService.debugOverrideCachedGitPath(dumper.exe);

      // Act
      final process = await startGitInCurrentDir(dumper.args);
      final out = await process.stdout.transform(systemEncoding.decoder).join();
      await process.exitCode;

      // Assert
      expect(_looksLikeEnvDump(out), isTrue);
    });
  });

  group('TRUYỀN executable tường minh → bỏ qua GitService.gitPath hoàn toàn',
      () {
    test(
        'runGit dùng ĐÚNG executable được truyền, không đụng tới cache dù '
        'cache đang trỏ vào path hỏng', () async {
      // Arrange — cache trỏ vào một path chắc chắn không chạy được, để nếu
      // runGit lỡ đọc gitPath thay vì dùng executable được truyền, lệnh sẽ
      // throw/fail rõ ràng chứ không âm thầm pass.
      GitService.debugOverrideCachedGitPath(
          '${tmp.path}/definitely-not-a-real-binary');
      final dumper = _envDumper;

      // Act — giống cách clone_repository_dialog.dart truyền executable tường minh.
      final result = await runGit(
        dumper.args,
        workingDir: tmp.path,
        executable: dumper.exe,
      );

      // Assert
      expect(_looksLikeEnvDump(result.stdout as String), isTrue);
    });
  });
}
