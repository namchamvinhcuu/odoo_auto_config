// Test HÀNH VI cho wrapper git `lib/services/git_process.dart`: env
// `GIT_TERMINAL_PROMPT=0` phải THẬT SỰ tới được process con, và env của tiến
// trình cha (PATH, HOME, SSH_AUTH_SOCK) KHÔNG bị mất.
//
// Vì sao cần: nếu env này rơi mất, git gặp repo cần credential sẽ CHỜ nhập trên
// stdin. Dialog chạy git đang disable nút đóng ⇒ user phải kill app. Đó là bug
// im lặng: không test nào khác của repo assert env, và không thể quan sát bằng
// cách chạy git thật trong test (không có tty ⇒ git fail sẵn, không phân biệt
// được có env hay không).
//
// Cách đo được mà vẫn thật: wrapper nhận `executable` (thêm vào để giữ git-path
// user tự cấu hình), nên trỏ nó vào chương trình IN RA ENV — `env` trên POSIX,
// `cmd /c set` trên Windows — rồi đọc stdout. Không mock, không đọc source.
//
// Nếu ai đó bỏ `environment: kGitEnvironment` hoặc thêm
// `includeParentEnvironment: false`, các test dưới ĐỎ.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_process.dart';

/// Chương trình in ra toàn bộ biến môi trường, theo OS.
({String exe, List<String> args}) get _envDumper => Platform.isWindows
    ? (exe: 'cmd', args: ['/c', 'set'])
    : (exe: 'env', args: <String>[]);

/// Tên biến PATH khác case trên Windows (`Path=`) — so sánh không phân biệt hoa
/// thường cho chắc.
bool _hasParentEnv(String out) => out.toLowerCase().contains('path=');

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('git_process_env_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('kGitEnvironment khai báo đúng GIT_TERMINAL_PROMPT=0', () {
    expect(kGitEnvironment['GIT_TERMINAL_PROMPT'], '0');
  });

  test('runGit truyền GIT_TERMINAL_PROMPT=0 xuống process con', () async {
    // Arrange
    final dumper = _envDumper;

    // Act
    final result = await runGit(
      dumper.args,
      workingDir: tmp.path,
      executable: dumper.exe,
    );

    // Assert
    final out = result.stdout as String;
    expect(out, contains('GIT_TERMINAL_PROMPT=0'),
        reason: 'thiếu env này ⇒ git treo chờ credential và dialog không đóng '
            'được (nút close bị disable khi process còn chạy)');
    expect(_hasParentEnv(out), isTrue,
        reason: 'env cha phải được kế thừa, nếu không git mất PATH/SSH_AUTH_SOCK '
            '⇒ credential helper và ssh-agent ngừng hoạt động');
  });

  test('startGit truyền GIT_TERMINAL_PROMPT=0 xuống process con', () async {
    // Arrange
    final dumper = _envDumper;

    // Act
    final process = await startGit(
      dumper.args,
      workingDir: tmp.path,
      executable: dumper.exe,
    );
    final out = await process.stdout.transform(systemEncoding.decoder).join();
    await process.exitCode;

    // Assert
    expect(out, contains('GIT_TERMINAL_PROMPT=0'));
    expect(_hasParentEnv(out), isTrue);
  });

  test(
      'startGitInCurrentDir (dùng cho clone — không có repo để cd vào) cũng '
      'truyền GIT_TERMINAL_PROMPT=0', () async {
    // Arrange
    final dumper = _envDumper;

    // Act
    final process = await startGitInCurrentDir(
      dumper.args,
      executable: dumper.exe,
    );
    final out = await process.stdout.transform(systemEncoding.decoder).join();
    await process.exitCode;

    // Assert — clone repo private là đúng ca dễ prompt nhất, nên nhánh này
    // không được hở.
    expect(out, contains('GIT_TERMINAL_PROMPT=0'));
    expect(_hasParentEnv(out), isTrue);
  });

  test('runGit chạy đúng trong workingDir được truyền', () async {
    // Arrange — đảm bảo wrapper không âm thầm chạy ở cwd của app (sai repo).
    final marker = Directory('${tmp.path}/marker')..createSync();
    final dumper = Platform.isWindows
        ? (exe: 'cmd', args: ['/c', 'cd'])
        : (exe: 'pwd', args: <String>[]);

    // Act
    final result = await runGit(
      dumper.args,
      workingDir: marker.path,
      executable: dumper.exe,
    );

    // Assert — macOS: /var là symlink của /private/var nên so sánh phần cuối.
    expect((result.stdout as String).trim(), endsWith('marker'));
  });
}
