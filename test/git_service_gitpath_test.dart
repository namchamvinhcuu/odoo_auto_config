// Test hành vi cho `GitService.gitPath` (lib/services/git_service.dart) sau
// fix "Xcode-license stub" (2026-09): một candidate path `File.exists()` là
// TRUE không còn đủ để được chọn — nó còn phải thực sự CHẠY được (verify bằng
// `--version` thật). Bug gốc: trên máy Nam, app đóng gói (launch từ Finder,
// không có PATH của `~/.zshrc`) resolve `'git'` trần theo PATH mặc định macOS
// và trúng `/usr/bin/git` (stub Xcode CLT) — file đó TỒN TẠI nhưng chạy thật
// bị lỗi "You have not agreed to the Xcode license agreements" (exit 69),
// trong khi git thật lại nằm ở `/opt/homebrew/bin/git`.
//
// `gitPath` hardcode 3 path macOS thật, khác nhau per-máy và không thể tạo
// "candidate hỏng" một cách tin cậy trên máy chạy test. Vì vậy logic chọn
// candidate được tách ra `GitService.debugFirstWorkingCandidate` — seam
// test-only, KHÔNG đổi public API của `gitPath`/`runGit`/`startGit`/
// `startGitInCurrentDir` — để test bằng fixture path tự tạo, chạy được trên
// mọi máy chạy `flutter test`.
//
// Mutation check đã làm khi viết test này (theo test-discipline, revert bằng
// Edit đảo ngược — KHÔNG git): đổi `&&` thành `||` trong
// `_firstWorkingCandidate` → test 'candidate exists but exits non-zero...'
// FAIL đúng như mong đợi (chọn nhầm candidate hỏng vì `File.exists()` một
// mình đã đủ `true`), sau đó revert lại `&&`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_service.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('git_service_gitpath_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    // Isolation — _cachedGitPath là static, sống suốt process test runner;
    // reset để override của test này không rò sang test khác trong cùng file
    // hoặc file test khác chạy trong cùng process.
    GitService.debugOverrideCachedGitPath(null);
  });

  /// Tạo 1 "candidate git" giả — chỉ cần thoát với [exitCode] cho trước, mô
  /// phỏng đúng phần quan trọng của bug thật: một file TỒN TẠI trên đĩa nhưng
  /// FAIL khi chạy thật (Xcode stub trả exit 69).
  Future<String> makeCandidate(String name, int exitCode) async {
    if (Platform.isWindows) {
      final file = File('${tmp.path}/$name.cmd');
      file.writeAsStringSync('@echo off\r\nexit /b $exitCode\r\n');
      return file.path;
    }
    final file = File('${tmp.path}/$name');
    file.writeAsStringSync('#!/bin/sh\nexit $exitCode\n');
    await Process.run('chmod', ['+x', file.path]);
    return file.path;
  }

  group('GitService.debugFirstWorkingCandidate — skip candidate tồn tại '
      'nhưng chạy hỏng', () {
    test(
        'candidate tồn tại nhưng exit non-zero (mô phỏng Xcode-license stub) '
        'bị SKIP, rơi xuống candidate kế tiếp chạy được', () async {
      // Arrange
      final broken = await makeCandidate('broken', 69);
      final working = await makeCandidate('working', 0);

      // Act
      final result =
          await GitService.debugFirstWorkingCandidate([broken, working]);

      // Assert
      expect(result, working,
          reason: 'candidate tồn tại + hỏng phải bị skip, không được chọn '
              'chỉ vì File.exists() true');
    });

    test('candidate không tồn tại trên đĩa bị skip, không throw', () async {
      // Arrange
      final working = await makeCandidate('working', 0);

      // Act
      final result = await GitService.debugFirstWorkingCandidate([
        '${tmp.path}/does-not-exist-anywhere',
        working,
      ]);

      // Assert
      expect(result, working);
    });

    test('candidate chạy được ĐẦU TIÊN thắng, dù candidate sau cũng chạy '
        'được', () async {
      // Arrange
      final first = await makeCandidate('first', 0);
      final second = await makeCandidate('second', 0);

      // Act
      final result =
          await GitService.debugFirstWorkingCandidate([first, second]);

      // Assert
      expect(result, first);
    });

    test('không candidate nào chạy được → null (caller rơi về bare "git")',
        () async {
      // Arrange
      final broken = await makeCandidate('broken', 69);

      // Act
      final result = await GitService.debugFirstWorkingCandidate([broken]);

      // Assert
      expect(result, isNull);
    });

    test('danh sách candidate rỗng → null', () async {
      final result = await GitService.debugFirstWorkingCandidate([]);
      expect(result, isNull);
    });
  });

  group('GitService.gitPath — cache', () {
    test(
        'giá trị đã cache short-circuit, KHÔNG đi qua vòng resolve candidate '
        'lại', () async {
      // Arrange — set trực tiếp vào cache một giá trị mà KHÔNG candidate
      // macOS thật nào (dù máy chạy test là gì) có thể tình cờ khớp.
      GitService.debugOverrideCachedGitPath('/tmp/fake-cached-git-marker');

      // Act
      final result = await GitService.gitPath;

      // Assert — nếu code lỡ bỏ qua nhánh cache (`if (_cachedGitPath != '
      // 'null) return ...`), gitPath sẽ chạy vòng resolve thật và KHÔNG BAO '
      // 'GIỜ trả về đúng chuỗi giả này.
      expect(result, '/tmp/fake-cached-git-marker');
    });

    test('gọi 2 lần liên tiếp trả về CÙNG giá trị đã cache (idempotent)',
        () async {
      // Arrange
      GitService.debugOverrideCachedGitPath('/tmp/fake-cached-git-marker-2');

      // Act
      final first = await GitService.gitPath;
      final second = await GitService.gitPath;

      // Assert
      expect(first, second);
      expect(second, '/tmp/fake-cached-git-marker-2');
    });
  });

  group('GitService.install — regression: cache phải bị invalidate sau '
      'install (reviewer finding 🟠, clone_repository_dialog._ensureGit / '
      'clone_odoo_dialog / environment_provider.autoSetup)', () {
    // Trước fix: `_cachedGitPath` sống vĩnh viễn cho tới lần đầu resolve —
    // flow "isInstalled() (cache 'not found') → install() → gitPath() ngay
    // sau" đọc lại đúng cache CŨ từ trước lúc install chạy, nên git vừa cài
    // xong trong session vẫn coi như "chưa tìm thấy". Dùng
    // `debugInstallerOverride` để verify cache-invalidation contract mà
    // KHÔNG cần spawn `xcode-select --install` / `winget` / `pkexec` thật
    // trên máy chạy test.

    tearDown(() {
      GitService.debugInstallerOverride = null;
    });

    test(
        'install() invalidate cache khi installer THÀNH CÔNG (exit 0) — '
        'regression_install_cache_invalidation', () async {
      // Arrange
      GitService.debugOverrideCachedGitPath('stale-path-before-install');
      GitService.debugInstallerOverride = (_) async => 0;

      // Act
      final exitCode = await GitService.install((_) {});

      // Assert
      expect(exitCode, 0);
      expect(GitService.debugCachedGitPath, isNull,
          reason: 'cache phải bị reset về null ngay sau install() để lần '
              'gitPath() kế tiếp re-scan thấy git vừa cài, không còn trả '
              'giá trị cache từ TRƯỚC lúc install chạy');
    });

    test(
        'install() VẪN invalidate cache khi installer FAIL (exit non-zero) — '
        'đúng yêu cầu "regardless of outcome"', () async {
      // Arrange — mô phỏng nhánh macOS chỉ mở dialog xcode-select rồi return
      // ngay (không đợi exit code thật), và nhánh lỗi thật (winget/pkexec
      // fail) — cả 2 đều PHẢI invalidate, không riêng nhánh thành công.
      GitService.debugOverrideCachedGitPath('stale-path-before-install-2');
      GitService.debugInstallerOverride = (_) async => -1;

      // Act
      final exitCode = await GitService.install((_) {});

      // Assert
      expect(exitCode, -1);
      expect(GitService.debugCachedGitPath, isNull,
          reason: 'invalidate phải xảy ra bất kể installer thành công hay '
              'fail — đây chính là điều finding 🟠 yêu cầu, KHÔNG chỉ '
              'invalidate ở nhánh happy-path');
    });
  });
}
