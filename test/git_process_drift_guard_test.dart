// Drift-guard: KHÔNG được gọi git trực tiếp qua `Process.run`/`Process.start`
// trong `lib/` — mọi lệnh git phải đi qua `runGit`/`startGit`/
// `startGitInCurrentDir` (lib/services/git_process.dart), nơi duy nhất pin
// `runInShell` + `GIT_TERMINAL_PROMPT=0`.
//
// Vì sao là test chứ không phải review: lần trước cả người lẫn `grep "'git'"`
// đều bỏ sót các call-site mà **executable là BIẾN** (`GitService.gitPath` — git
// path do user cấu hình). Grep literal không thấy chúng. Test này quét source và
// nhận diện cả dạng biến.
//
// Heuristic (2 cờ hiệu, OR):
//   1. Biểu thức executable có token `git` — bắt `'git'`, `git`, `gitPath`,
//      `_gitPath`, `'/usr/bin/git'`. Đây là cờ chính.
//   2. Phần tử ĐẦU của args là subcommand chỉ git mới có (`clone`, `rev-parse`,
//      `checkout`…). Cờ phụ, dùng khi executable là biến tên khác.
// Cố ý KHÔNG đưa vào danh sách subcommand các từ mà CLI khác trong repo cũng
// dùng làm arg đầu (`start`, `exec`, `pull`, `push`, `logs`, `info`, `list`,
// `install`, `--version`…) — thà bỏ sót một ca lạ còn hơn báo động sai với
// docker/pip/systemctl và làm test thành nhiễu. Ca thực tế nào cũng có
// executable tên git, nên cờ 1 đủ gánh.
//
// Giới hạn đã biết (ghi rõ thay vì giả vờ cover): đây là quét text, không parse
// AST. Không bắt được lệnh git chạy GIÁN TIẾP qua shell script / `bash -c`
// (vd git_pull_dialog chạy script .sh có git bên trong — chỗ đó phải tự truyền
// `kGitEnvironment`, xem docstring tại đó).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Một call-site bị coi là "gọi git thô".
typedef GitCallSite = ({String path, int line, String executable, String args});

/// Subcommand đặc trưng của git — CHỈ giữ những từ mà **không CLI nào khác** có
/// thể dùng làm arg đầu, kể cả trong tương lai.
///
/// Cố ý BỎ `status` / `commit` / `branch` / `remote` / `merge` (review vòng 2,
/// 🟡#4): `systemctl status`, `docker commit`, `git`-lookalike khác đều dùng
/// chúng ⇒ một lần thêm `Process.run('systemctl', ['status', …])` là guard đỏ với
/// message SAI, và đó chính là cách guard bị người sau disable. Cờ-1 (token
/// `git` trong biểu thức executable) mới là cờ gánh chính — mutation 2 chiều ở
/// cuối file chứng minh nó vẫn bắt được cả `Process.run('git', …)` lẫn dạng
/// executable là BIẾN sau khi siết set này.
const kGitOnlySubcommands = {
  'clone',
  'fetch',
  'rev-list',
  'rev-parse',
  'ls-remote',
  'ls-files',
  'symbolic-ref',
  'show-ref',
  'for-each-ref',
  'cherry-pick',
  'stash',
  'worktree',
  'rebase',
  'describe',
};

/// Ngoại lệ CÓ CHỦ Ý — mỗi dòng phải kèm lý do, và phải hẹp (khớp cả args) để
/// không vô tình mở cửa cho call-site khác trong cùng file.
const kWhitelist = <({String path, String? argsContains, String why})>[
  (
    path: 'lib/services/git_process.dart',
    argsContains: null,
    why: 'chính là wrapper — nơi duy nhất được gọi Process trực tiếp cho git',
  ),
  (
    path: 'lib/services/git_service.dart',
    argsContains: "'--version'",
    why: 'dò git có tồn tại / ở đâu: không repo, không mạng, không thể prompt '
        'credential ⇒ không cần (và không thể dùng) wrapper vốn đòi workingDir',
  ),
];

/// Xoá comment `//` (giữ nguyên độ dài + số dòng) để không quét trúng ví dụ code
/// trong docstring. Chỉ cắt khi `//` nằm ngoài string literal (đếm quote chưa
/// escape trước đó).
String stripLineComments(String source) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    var singleQuotes = 0;
    var doubleQuotes = 0;
    var cut = -1;
    for (var i = 0; i < line.length - 1; i++) {
      final c = line[i];
      final escaped = i > 0 && line[i - 1] == r'\';
      if (c == "'" && !escaped) singleQuotes++;
      if (c == '"' && !escaped) doubleQuotes++;
      if (c == '/' &&
          line[i + 1] == '/' &&
          singleQuotes % 2 == 0 &&
          doubleQuotes % 2 == 0) {
        cut = i;
        break;
      }
    }
    out.writeln(cut < 0 ? line : line.substring(0, cut));
  }
  // writeln thêm '\n' cuối; bỏ đi để số dòng khớp source gốc.
  final s = out.toString();
  return s.endsWith('\n') ? s.substring(0, s.length - 1) : s;
}

/// Tách các argument top-level của một chuỗi trong ngoặc (bỏ qua dấu ngoặc/quote
/// lồng nhau).
List<String> splitTopLevelArgs(String argText) {
  final parts = <String>[];
  var depth = 0;
  String? quote;
  var start = 0;
  for (var i = 0; i < argText.length; i++) {
    final c = argText[i];
    final escaped = i > 0 && argText[i - 1] == r'\';
    if (quote != null) {
      if (c == quote && !escaped) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      parts.add(argText.substring(start, i).trim());
      start = i + 1;
    }
  }
  if (start < argText.length) parts.add(argText.substring(start).trim());
  return parts;
}

/// `git`, `gitPath`, `_gitPath`, `'git'`, `'/usr/bin/git'` → true.
/// `digit`, `docker`, `executable` → false.
bool executableLooksLikeGit(String expr) =>
    RegExp(r'(?<![A-Za-z0-9])git', caseSensitive: false).hasMatch(expr);

/// Args là list literal và phần tử đầu là subcommand chỉ git mới có.
bool argsStartWithGitSubcommand(String? expr) {
  if (expr == null) return false;
  final m = RegExp(r"^(?:const\s*)?\[\s*'([^']+)'").firstMatch(expr.trim());
  return m != null && kGitOnlySubcommands.contains(m.group(1));
}

/// Quét 1 file source, trả về các call-site chạy git mà không qua wrapper.
List<GitCallSite> findRawGitCalls(String path, String rawSource) {
  final source = stripLineComments(rawSource);
  final result = <GitCallSite>[];
  final pattern = RegExp(r'Process\.(?:run|start|runSync|startSync)\s*\(');
  for (final match in pattern.allMatches(source)) {
    // Lấy phần trong ngoặc, cân bằng dấu ngoặc.
    var depth = 1;
    String? quote;
    var i = match.end;
    for (; i < source.length && depth > 0; i++) {
      final c = source[i];
      final escaped = i > 0 && source[i - 1] == r'\';
      if (quote != null) {
        if (c == quote && !escaped) quote = null;
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(' || c == '[' || c == '{') {
        depth++;
      } else if (c == ')' || c == ']' || c == '}') {
        depth--;
      }
    }
    final argText = source.substring(match.end, i > 0 ? i - 1 : match.end);
    final args = splitTopLevelArgs(argText);
    if (args.isEmpty) continue;
    final executable = args.first;
    final argsExpr = args.length > 1 && !args[1].contains(':') ? args[1] : null;

    if (!executableLooksLikeGit(executable) &&
        !argsStartWithGitSubcommand(argsExpr)) {
      continue;
    }
    final line = source.substring(0, match.start).split('\n').length;
    result.add((
      path: path,
      line: line,
      executable: executable,
      args: argsExpr ?? '',
    ));
  }
  return result;
}

bool isWhitelisted(GitCallSite site, String rawSource) {
  for (final entry in kWhitelist) {
    if (site.path != entry.path) continue;
    if (entry.argsContains == null) return true;
    if (site.args.contains(entry.argsContains!)) return true;
  }
  return false;
}

void main() {
  group('heuristic — phải BẮT được dạng đã từng lọt', () {
    test('executable là BIẾN tên git (đúng lỗ grep literal bỏ sót)', () {
      // Arrange — dạng thật ở clone_repository_dialog trước khi sửa.
      const src = '''
        final git = await GitService.gitPath;
        final process = await Process.start(git, args, runInShell: true);
      ''';

      // Act
      final found = findRawGitCalls('lib/x.dart', src);

      // Assert
      expect(found, hasLength(1));
      expect(found.first.executable, 'git');
    });

    test('executable là literal "git"', () {
      const src = '''
        await Process.run('git', ['status', '--porcelain'],
            workingDirectory: dir, runInShell: true);
      ''';
      expect(findRawGitCalls('lib/x.dart', src), hasLength(1));
    });

    test('executable là path đầy đủ tới git', () {
      const src = "await Process.run('/usr/bin/git', ['log', '-1']);";
      expect(findRawGitCalls('lib/x.dart', src), hasLength(1));
    });

    test('executable là gitPath / _gitBin', () {
      const src = '''
        await Process.run(gitPath, ['fetch', '--prune'], workingDirectory: d);
        await Process.start(_gitBin, ['pull'], workingDirectory: d);
      ''';
      expect(findRawGitCalls('lib/x.dart', src), hasLength(2));
    });

    test('executable tên lạ nhưng args là subcommand chỉ git mới có', () {
      const src = "await Process.run(exe, ['rev-parse', '--abbrev-ref', 'HEAD'],"
          ' workingDirectory: d);';
      expect(findRawGitCalls('lib/x.dart', src), hasLength(1));
    });

    test('bắt được cả invocation viết trên nhiều dòng + báo đúng số dòng', () {
      const src = '''
        void f() {
          final r = await Process.run(
            'git',
            ['commit', '-m', msg],
            workingDirectory: dir,
          );
        }
      ''';

      final found = findRawGitCalls('lib/x.dart', src);

      expect(found, hasLength(1));
      // Dart bỏ newline đầu của multiline string ⇒ `void f() {` là dòng 1,
      // `final r = await Process.run(` là dòng 2.
      expect(found.first.line, 2, reason: 'line phải trỏ vào Process.run(');
    });
  });

  group('heuristic — KHÔNG được báo động sai', () {
    test('docker / pip / systemctl / mkcert / open / chmod / shutdown / cmd', () {
      // Arrange — copy đúng dạng đang có trong lib/.
      const src = '''
        await Process.run(docker, ['start', container], runInShell: true);
        await Process.run(docker, ['compose', 'up', '-d'], runInShell: true);
        await Process.run(docker, ['--version'], runInShell: true);
        await Process.run(docker, ['exec', '-i', name, 'psql'], runInShell: true);
        await Process.run(pip, ['list', '--format=json'], runInShell: true);
        await Process.run(pip, ['install', ...args], runInShell: true);
        await Process.run('systemctl', ['--user', 'start', 'docker-desktop']);
        await Process.run(mkcert, ['-version'], runInShell: true);
        await Process.run('open', ['-a', primary], runInShell: true);
        await Process.run('open', [url], runInShell: true);
        await Process.run('chmod', ['+x', scriptPath], runInShell: true);
        await Process.run('shutdown', ['/r', '/t', '5'], runInShell: true);
        await Process.run('cmd', ['/c', 'start', url], runInShell: true);
        await Process.run('xdg-open', [path], runInShell: true);
        await Process.run('explorer', [path], runInShell: true);
        await Process.run('code', [path], runInShell: true);
        await Process.run('curl', ['-fsSL', url], runInShell: true);
        await Process.run('powershell', ['-Command', script], runInShell: true);
        await Process.run('bash', [scriptPath], runInShell: true);
        await Process.run('wsl', ['--status'], runInShell: true);
      ''';

      // Act
      final found = findRawGitCalls('lib/x.dart', src);

      // Assert
      expect(found, isEmpty, reason: 'báo động sai làm test thành nhiễu → bị bỏ');
    });

    test('executable là biến shell (script có git bên trong) không bị flag', () {
      // Arrange — git_pull_dialog: powershell/bash chạy script, đã tự truyền
      // kGitEnvironment; guard này không cố kiểm ca đó.
      const src = '''
        final process = await Process.start(
          executable,
          args,
          workingDirectory: widget.projectPath,
          environment: kGitEnvironment,
        );
      ''';
      expect(findRawGitCalls('lib/x.dart', src), isEmpty);
    });

    test('ví dụ code trong comment không bị tính', () {
      const src = '''
        /// Dùng thay cho Process.run('git', ...) trực tiếp.
        // await Process.run('git', ['status']);
        await runGit(['status'], workingDir: dir);
      ''';
      expect(findRawGitCalls('lib/x.dart', src), isEmpty);
    });

    test('gọi qua wrapper không bị tính', () {
      const src = '''
        await runGit(['fetch', '--prune'], workingDir: d);
        await startGit(['pull'], workingDir: d);
        await startGitInCurrentDir(['clone', url, dest], executable: git);
      ''';
      expect(findRawGitCalls('lib/x.dart', src), isEmpty);
    });

    test(
        'CLI khác dùng subcommand trùng tên git (systemctl status / docker '
        'commit / docker remote…) không bị flag — review 🟡#4', () {
      // Arrange — các lệnh HOÀN TOÀN hợp lệ mà set subcommand cũ sẽ báo sai.
      const src = '''
        await Process.run('systemctl', ['status', unit], runInShell: true);
        await Process.run(docker, ['commit', containerId, tag]);
        await Process.run(docker, ['stats', '--no-stream']);
        await Process.run('brew', ['status']);
        await Process.run(npm, ['merge-base-hook']);
        await Process.run(psql, ['branch']);
      ''';

      // Act
      final found = findRawGitCalls('lib/x.dart', src);

      // Assert
      expect(found, isEmpty,
          reason: 'guard đỏ với message SAI là cách nhanh nhất để nó bị xoá');
      for (final word in ['status', 'commit', 'branch', 'remote', 'merge']) {
        expect(kGitOnlySubcommands, isNot(contains(word)),
            reason: 'đừng thêm lại "$word": CLI khác cũng dùng làm arg đầu');
      }
    });

    test('"digit" trong tên biến không bị nhận là git', () {
      expect(executableLooksLikeGit('digitTool'), isFalse);
      expect(executableLooksLikeGit('gitPath'), isTrue);
      expect(executableLooksLikeGit('_gitPath'), isTrue);
    });
  });

  test('lib/ KHÔNG còn lệnh git thô nào ngoài whitelist', () async {
    // Arrange
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'cwd của flutter test phải là root package');

    // Act
    final violations = <GitCallSite>[];
    for (final file in files) {
      final rel = file.path.replaceAll(r'\', '/');
      final source = file.readAsStringSync();
      for (final site in findRawGitCalls(rel, source)) {
        if (!isWhitelisted(site, source)) violations.add(site);
      }
    }

    // Assert
    expect(
      violations,
      isEmpty,
      reason: violations.isEmpty
          ? ''
          : 'Lệnh git chạy ngoài wrapper — dùng runGit/startGit '
              '(hoặc startGitInCurrentDir cho clone) trong '
              'lib/services/git_process.dart để env GIT_TERMINAL_PROMPT=0 '
              'không bị rơi mất:\n'
              '${violations.map((v) => '  ${v.path}:${v.line} → '
                  'executable=${v.executable} args=${v.args}').join('\n')}',
    );
  });

  test('whitelist vẫn khớp đúng 2 ngoại lệ đã ghi (không rộng hơn)', () async {
    // Arrange — nếu ai đó thêm call-site git thô KHÁC vào git_service.dart,
    // whitelist theo args '--version' sẽ không che nó.
    final source = File('lib/services/git_service.dart').readAsStringSync();

    // Act
    final sites = findRawGitCalls('lib/services/git_service.dart', source);

    // Assert
    expect(sites, hasLength(2), reason: 'git_service chỉ được có 2 lần dò --version');
    for (final site in sites) {
      expect(site.args, contains("'--version'"));
      expect(isWhitelisted(site, source), isTrue);
    }
  });
}
