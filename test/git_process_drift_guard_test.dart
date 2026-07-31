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
//
// ── Phần 2 (mở rộng): `gh` cũng phải mang `kGitEnvironment` ──
// `gh` spawn git bên dưới ⇒ nếu `runGh`/`startGh` (lib/services/platform_service.dart)
// không merge `kGitEnvironment` thì lỗ "dialog treo vì git chờ nhập credential"
// quay lại qua đường gh. Guard này KHÁC guard git ở trên về bản chất: gh KHÔNG có
// wrapper riêng nên không thể cấm `Process.run`, chỉ có thể đòi 2 wrapper đó
// truyền env đúng.
//
// Vì sao vẫn là quét text mà KHÔNG xanh-giả: `runGh` không nhận `executable`
// (khác `runGit`), nó tự resolve `ghPath` ⇒ không có seam để chạy thật với một
// chương trình in-env như `git_process_env_test.dart` làm cho git. Hai lựa chọn
// trung thực là (a) quét text như dưới, hoặc (b) thêm tham số `executable` cho
// `runGh`/`startGh` rồi test hành vi thật — (b) là đổi public API nên để main
// quyết. Guard dưới nói rõ nó chứng minh được gì: mọi nhánh `Process` trong 2
// wrapper đó truyền đúng biến env đã merge, và thứ tự spread không nuốt quyền
// override của caller. Nó KHÔNG chứng minh env tới được process con (đó là việc
// của (b)). Heuristic được test 2 chiều bằng source tổng hợp ngay dưới, nên nó
// không phải một assert luôn-xanh.

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

// ───────────────────────── phần 2: guard cho `gh` ─────────────────────────

/// Chữ ký 2 wrapper gh. Đổi chữ ký thì guard báo "không tìm thấy" — cố ý: người
/// đổi phải nhìn lại chỗ này chứ không được để guard im lặng hết tác dụng.
const kGhWrapperSignatures = [
  'static Future<ProcessResult> runGh(',
  'static Future<Process> startGh(',
];

/// `gh`, `ghPath`, `_ghPath`, `'gh'`, `'/opt/homebrew/bin/gh'` → true.
/// `ghost`, `github`, `light` → false (theo sau `gh` là chữ thường/số ⇒ bỏ).
bool executableLooksLikeGh(String expr) =>
    RegExp(r'(?<![A-Za-z0-9])gh(?![a-z0-9])').hasMatch(expr);

/// Chỉ số ngay SAU dấu `)` đóng của cặp ngoặc mở tại [openParen]; `null` nếu
/// không cân được.
///
/// Cần bước này vì danh sách tham số của Dart chứa `{…}` (named parameters) —
/// nhảy thẳng tới `{` đầu tiên sau chữ ký sẽ lấy nhầm khối tham số làm thân
/// method, và guard khi đó KHÔNG BAO GIỜ thấy dòng merge env (xanh/đỏ đều sai).
int? parenEndAt(String source, int openParen) {
  var depth = 0;
  String? quote;
  for (var i = openParen; i < source.length; i++) {
    final c = source[i];
    final escaped = i > 0 && source[i - 1] == r'\';
    if (quote != null) {
      if (c == quote && !escaped) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return null;
}

/// Khối `{…}` đầu tiên kể từ [from], cân bằng ngoặc và bỏ qua nội dung string.
/// `null` nếu không cân được.
String? braceBlockAt(String source, int from) {
  final start = source.indexOf('{', from);
  if (start < 0) return null;
  var depth = 0;
  String? quote;
  for (var i = start; i < source.length; i++) {
    final c = source[i];
    final escaped = i > 0 && source[i - 1] == r'\';
    if (quote != null) {
      if (c == quote && !escaped) quote = null;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  return null;
}

/// Argument top-level của mỗi `Process.run/start(...)` trong [snippet].
List<List<String>> findProcessInvocations(String snippet) {
  final calls = <List<String>>[];
  final pattern = RegExp(r'Process\.(?:run|start|runSync|startSync)\s*\(');
  for (final match in pattern.allMatches(snippet)) {
    var depth = 1;
    String? quote;
    var i = match.end;
    for (; i < snippet.length && depth > 0; i++) {
      final c = snippet[i];
      final escaped = i > 0 && snippet[i - 1] == r'\';
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
    calls.add(splitTopLevelArgs(snippet.substring(match.end, i - 1)));
  }
  return calls;
}

/// Giá trị của named argument [name], hoặc `null` nếu không truyền.
String? namedArg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name:')) return a.substring(name.length + 1).trim();
  }
  return null;
}

/// Vi phạm env-merge của 2 wrapper gh trong [rawSource]. Rỗng = sạch.
///
/// Đòi đúng 3 điều, mỗi điều tương ứng một cách drift đã thấy thật:
///   1. có `final <env> = {...kGitEnvironment, ...?environment};` — thiếu = quên hẳn;
///   2. `...?environment` đứng SAU — viết đảo thì env caller truyền vào bị
///      `kGitEnvironment` ghi đè, tức "override được" chỉ là ảo tưởng;
///   3. MỌI nhánh `Process` trong thân method dùng đúng biến đó — sửa một nhánh
///      quên nhánh kia là lỗi cross-platform kinh điển (nhánh Windows
///      path-có-space là nhánh hay bị bỏ quên). Hằng `kGitEnvironment` trần KHÔNG
///      được coi là đạt: nó rơi mất env của caller.
///
/// Cách viết được chấp nhận cho điều 1: có/không type annotation
/// (`final Map<String, String> env = …`), có/không type argument
/// (`= <String, String>{…}`).
///
/// GIỚI HẠN đã biết — các dạng tương đương mà guard này SẼ báo "thiếu merge":
/// `if (environment != null) ...environment` · tách helper
/// `ghEnvironment(environment)` · inline map ngay tại call site. Nếu ai refactor
/// sang một trong số đó thì **cập nhật guard**, đừng xoá nó: điều cần canh vẫn
/// là "mọi nhánh spawn gh mang env đã merge, caller override được".
List<String> findGhEnvDrift(String rawSource) {
  final src = stripLineComments(rawSource);
  final problems = <String>[];
  for (final sig in kGhWrapperSignatures) {
    final start = src.indexOf(sig);
    if (start < 0) {
      problems.add('$sig → không tìm thấy (đổi chữ ký thì cập nhật guard)');
      continue;
    }
    // Chữ ký kết thúc bằng `(` ⇒ nhảy qua hết danh sách tham số trước khi tìm
    // thân method (tham số named cũng dùng `{…}`).
    final afterParams = parenEndAt(src, start + sig.length - 1);
    final body =
        afterParams == null ? null : braceBlockAt(src, afterParams);
    if (body == null) {
      problems.add('$sig → không cân được ngoặc thân method');
      continue;
    }
    // Type annotation (`final Map<String, String> env = …`) và type argument
    // (`= <String, String>{…}`) đều tuỳ chọn: cả hai là cách viết tương đương
    // (thậm chí rõ hơn), guard mà đỏ vì chúng thì thành nhiễu → bị disable.
    final decl = RegExp(
      r'(?:final|const|var)\s+(?:[\w.]+(?:<[^>]*>)?\s+)?(\w+)\s*=\s*'
      r'(?:<[^>]*>\s*)?\{\s*\.\.\.\s*kGitEnvironment\s*,'
      r'\s*\.\.\.\?\s*environment\s*,?\s*\}',
    ).firstMatch(body);
    if (decl == null) {
      problems.add(
        '$sig → thiếu `{...kGitEnvironment, ...?environment}` đúng thứ tự '
        '(spread của caller phải đứng SAU để override được từng key)',
      );
      continue;
    }
    final envVar = decl.group(1)!;
    final calls = findProcessInvocations(body);
    if (calls.length < 2) {
      problems.add('$sig → chỉ thấy ${calls.length} lần gọi Process; wrapper có '
          '2 nhánh (Windows path-có-space / mặc định) — guard mất hiệu lực nếu '
          'không thấy đủ');
    }
    for (final args in calls) {
      final env = namedArg(args, 'environment');
      // Chỉ chấp nhận ĐÚNG biến đã merge. Hằng `kGitEnvironment` trần KHÔNG được
      // tha (review 🟠 vòng 3): nhánh đó giữ GIT_TERMINAL_PROMPT nhưng rơi mất
      // env do caller truyền vào, mà mắt người đọc lại thấy "có kGitEnvironment"
      // nên tưởng ổn — đúng loại drift guard này sinh ra để bắt.
      if (env != envVar) {
        problems.add('$sig → một nhánh Process truyền '
            '`environment: ${env ?? '(không truyền)'}` thay vì `$envVar`');
      }
    }
  }
  return problems;
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

  group('gh — runGh/startGh phải merge kGitEnvironment', () {
    const ghFile = 'lib/services/platform_service.dart';

    /// Wrapper viết ĐÚNG — dùng làm mốc "không báo động sai".
    const goodSource = '''
      static Future<ProcessResult> runGh(List<String> args, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async {
        final gh = await ghPath;
        final env = {...kGitEnvironment, ...?environment};
        if (isWindows && gh.contains(' ')) {
          return Process.run(gh, args,
              workingDirectory: workingDirectory, environment: env);
        }
        return Process.run(gh, args,
            workingDirectory: workingDirectory, runInShell: true, environment: env);
      }

      static Future<Process> startGh(List<String> args, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async {
        final gh = await ghPath;
        final env = {...kGitEnvironment, ...?environment};
        if (isWindows && gh.contains(' ')) {
          return Process.start(gh, args,
              workingDirectory: workingDirectory, environment: env);
        }
        return Process.start(gh, args,
            workingDirectory: workingDirectory, runInShell: true, environment: env);
      }
    ''';

    test('source ĐÚNG chuẩn → không vi phạm (guard không nhiễu)', () {
      expect(findGhEnvDrift(goodSource), isEmpty);
    });

    test(
        'cách viết tương đương (type annotation / type argument) KHÔNG bị báo '
        'thiếu merge (review 🟡 vòng 3)', () {
      // Arrange — hai dạng rõ-hơn mà guard vòng 2 báo đỏ oan. Guard nhiễu là
      // guard sẽ bị người sau disable, nên đây là ca chống-nhiễu, không phải nới
      // lỏng: điều kiện "kGitEnvironment trước, ...?environment sau" vẫn nguyên.
      final annotated = goodSource.replaceAll(
        'final env = {...kGitEnvironment, ...?environment};',
        'final Map<String, String> env = {...kGitEnvironment, ...?environment};',
      );
      final typeArgs = goodSource.replaceAll(
        'final env = {...kGitEnvironment, ...?environment};',
        'final env = <String, String>{...kGitEnvironment, ...?environment};',
      );

      // Act + Assert
      expect(findGhEnvDrift(annotated), isEmpty, reason: 'type annotation');
      expect(findGhEnvDrift(typeArgs), isEmpty, reason: 'type argument');
    });

    test('sửa 1 nhánh quên nhánh kia → guard bắt được', () {
      // Arrange — nhánh Windows path-có-space bị bỏ quên, đúng kiểu drift
      // cross-platform mà repo này đã dính một lần với runInShell.
      final src = goodSource.replaceFirst(
        '''return Process.run(gh, args,
              workingDirectory: workingDirectory, environment: env);''',
        '''return Process.run(gh, args,
              workingDirectory: workingDirectory, environment: environment);''',
      );

      // Act
      final problems = findGhEnvDrift(src);

      // Assert
      expect(problems, hasLength(1));
      expect(problems.single, contains('environment: environment'));
    });

    test(
        'một nhánh truyền HẰNG `kGitEnvironment` thay vì biến đã merge → guard '
        'bắt được (review 🟠 vòng 3)', () {
      // Arrange — nhánh Windows dùng thẳng hằng. Đây là drift KHÓ thấy nhất:
      // mắt người đọc thấy chữ `kGitEnvironment` nên tưởng ổn, nhưng nhánh đó
      // rơi mất env do caller truyền vào (vd `GH_TOKEN` của create_pr_dialog)
      // ⇒ đúng thứ điều-3 trong docstring nói phải canh. Guard vòng 2 có mệnh đề
      // `env != 'kGitEnvironment'` nên bỏ qua ca này — đã sửa.
      final src = goodSource.replaceFirst(
        '''return Process.run(gh, args,
              workingDirectory: workingDirectory, environment: env);''',
        '''return Process.run(gh, args,
              workingDirectory: workingDirectory, environment: kGitEnvironment);''',
      );

      // Act
      final problems = findGhEnvDrift(src);

      // Assert
      expect(problems, hasLength(1));
      expect(problems.single, contains('environment: kGitEnvironment'));
    });

    test('spread viết đảo thứ tự → guard bắt được (override chỉ là ảo tưởng)',
        () {
      // Arrange — `{...?environment, ...kGitEnvironment}`: key caller truyền
      // vào bị hằng ghi đè, nên GIT_TERMINAL_PROMPT không bao giờ override được.
      final src = goodSource.replaceAll(
        '{...kGitEnvironment, ...?environment}',
        '{...?environment, ...kGitEnvironment}',
      );

      // Act + Assert — cả 2 wrapper cùng đỏ.
      expect(findGhEnvDrift(src), hasLength(2));
    });

    test('bỏ hẳn merge → guard bắt được', () {
      final src = goodSource
          .replaceAll('final env = {...kGitEnvironment, ...?environment};', '')
          .replaceAll('environment: env', 'environment: environment');
      expect(findGhEnvDrift(src), hasLength(2));
    });

    test('platform_service.dart THẬT: cả 2 wrapper gh đều merge đúng', () {
      // Arrange
      final source = File(ghFile).readAsStringSync();

      // Act
      final problems = findGhEnvDrift(source);

      // Assert
      expect(
        problems,
        isEmpty,
        reason: problems.isEmpty
            ? ''
            : '`gh` spawn git bên dưới; mất kGitEnvironment là mở lại lỗ dialog '
                'treo vì git chờ credential:\n  ${problems.join('\n  ')}',
      );
      // Invariant thật: env lấy TỪ nguồn duy nhất, không chép literal sang đây.
      // Cố ý KHÔNG khoá vào chuỗi `show kGitEnvironment;` — thêm symbol vào
      // `show` hoặc bỏ `show` đều hợp lệ và sẽ làm test đỏ oan (review 🟡 vòng 3).
      expect(source, matches(RegExp(r"import 'git_process\.dart'[^;]*;")),
          reason: 'phải import từ git_process.dart, không tự khai env riêng');
      expect(source, isNot(contains("'GIT_TERMINAL_PROMPT'")),
          reason: 'chép lại literal = có 2 nguồn sự thật; sửa 1 chỗ quên chỗ kia '
              'là cách lỗ này quay lại');
    });

    test('không file nào khác trong lib/ spawn gh thô', () {
      // Arrange — gh chỉ được chạy qua 2 wrapper trên; nơi khác gọi thẳng
      // Process là bỏ qua env merge mà guard trên không nhìn tới.
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.replaceAll(r'\', '/').endsWith(ghFile))
          .toList();

      // Act
      final sites = <String>[];
      for (final file in files) {
        final src = stripLineComments(file.readAsStringSync());
        for (final args in findProcessInvocations(src)) {
          if (args.isNotEmpty && executableLooksLikeGh(args.first)) {
            sites.add('${file.path} → ${args.first}');
          }
        }
      }

      // Assert
      expect(sites, isEmpty,
          reason: 'dùng PlatformService.runGh/startGh:\n  ${sites.join('\n  ')}');
    });

    test('"ghost"/"github" không bị nhận nhầm là gh', () {
      expect(executableLooksLikeGh('ghostscript'), isFalse);
      expect(executableLooksLikeGh('githubCli'), isFalse);
      expect(executableLooksLikeGh('gh'), isTrue);
      expect(executableLooksLikeGh('ghPath'), isTrue);
      expect(executableLooksLikeGh("'/opt/homebrew/bin/gh'"), isTrue);
    });
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
