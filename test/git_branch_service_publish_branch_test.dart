// Test cho `GitBranchService.publishBranch` — đường DUY NHẤT trong app tạo empty
// commit (`git commit --allow-empty`), và chỉ trong MỘT nhánh của nó.
//
// ── Vì sao file này tồn tại ──
// `publishBranch` là hành động ghi (tạo commit + đẩy branch mới lên origin) và
// cho tới nay KHÔNG có test nào chạm tới nó. Ba đặc điểm cần được canh:
//
//   1. Empty commit chỉ được tạo khi [branch] ĐÚNG LÀ branch đang checkout.
//      `git commit` luôn ghi vào HEAD, nên làm việc đó cho branch khác thì commit
//      rơi vào branch người dùng đang đứng (bẩn `main`) còn branch được publish
//      lên origin mà không có commit riêng — sai cả hai đầu. Branch khác ⇒ chỉ
//      `push -u origin <branch>` trần.
//   2. "Empty commit vô điều kiện" CHƯA BAO GIỜ là bất biến của app: 2 trong 3
//      đường publish không tạo commit nào — `SimpleGitPushDialog`
//      (`lib/screens/other_projects/simple_git_push_dialog.dart:22-25`) và
//      `GitActionDialog._publishRepo`
//      (`lib/screens/odoo_workspace/git_action_dialog.dart:111-121`) đều `push -u`
//      trần. Vậy nên đừng đọc file này thành "phải luôn commit"; điều được canh là
//      ĐÚNG NHÁNH NÀO commit.
//      (Comment ở `repo_tile.dart:189-202` vẫn đúng và KHÔNG stale: tile chỉ
//      publish `repo.branch`, tức luôn là branch hiện tại ⇒ nó rơi vào nhánh có
//      empty commit.)
//   3. Nó set upstream bằng `-u`. Mất `-u` thì branch vẫn lên remote nhưng lần
//      sau `git push` trần sẽ fail và badge/gate `hasUpstream` đọc sai trạng
//      thái.
//
// Cả ba đều được canh bằng assert riêng ⇒ mutation xoá từng cái phải có test
// đỏ (số đo trong /tmp/codemap-leftovers-tests.md).
//
// ── Cách test ──
// Git fixture THẬT (`Process.run`), không mock — cùng lối với
// `git_branch_service_publishable_count_test.dart` và
// `git_branch_service_can_publish_test.dart`: repo tạm trong `systemTemp`, bare
// remote local đóng vai `origin`, mọi assert đọc lại trạng thái repo bằng git
// chứ không đọc lại giá trị mà test tự đặt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/services/git_branch_service.dart';
import 'package:path/path.dart' as p;

/// Chạy 1 lệnh git trong [cwd], fail test nếu exitCode != 0.
Future<void> _git(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
}

/// Như [_git] nhưng trả stdout đã trim — dùng cho assert đọc trạng thái repo.
Future<String> _gitOut(List<String> args, String cwd) async {
  final r = await Process.run('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    fail('git ${args.join(' ')} (cwd=$cwd) failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

/// Đảm bảo commit không bị chặn bởi global hooks / thiếu user.* config.
///
/// `push.autoSetupRemote=false` được ghi tường minh (dù đó là default của git)
/// để test không phụ thuộc config global của máy chạy: máy nào bật cờ đó thì
/// `git push origin <branch>` cũng tự set upstream, và assert về `-u` sẽ xanh
/// giả.
Future<void> _configIdentity(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
  await _git(['config', 'push.autoSetupRemote', 'false'], cwd);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('git_publish_branch_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tạo [count] commit trong [cwd].
  Future<void> commits(String cwd, int count, String prefix) async {
    for (var i = 0; i < count; i++) {
      File(p.join(cwd, '$prefix-$i.txt')).writeAsStringSync('$prefix$i\n');
      await _git(['add', '.'], cwd);
      await _git(['commit', '-q', '-m', '$prefix-$i'], cwd);
    }
  }

  /// Clone từ bare remote, branch `main` đã push (có upstream).
  Future<String> clonedRepo() async {
    final remotePath = p.join(tmp.path, 'remote.git');
    final localPath = p.join(tmp.path, 'local');
    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);
    await _git(['clone', '-q', remotePath, localPath], tmp.path);
    await _configIdentity(localPath);
    File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-q', '-m', 'initial'], localPath);
    await _git(['push', '-q', '-u', 'origin', 'main'], localPath);
    return localPath;
  }

  /// Repo standalone (`git init`, KHÔNG remote) với 1 commit.
  Future<String> soloRepo() async {
    final dir = p.join(tmp.path, 'solo');
    Directory(dir).createSync(recursive: true);
    await _git(['init', '-q', '-b', 'main', '.'], dir);
    await _configIdentity(dir);
    await commits(dir, 1, 'solo');
    return dir;
  }

  /// Upstream đang cấu hình cho [branch], hoặc `null` nếu chưa có.
  Future<String?> upstreamOf(String dir, String branch) async {
    final r = await Process.run(
      'git',
      ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '$branch@{u}'],
      workingDirectory: dir,
    );
    if (r.exitCode != 0) return null;
    return (r.stdout as String).trim();
  }

  test(
      'happy: branch mới CHƯA có commit riêng → push thành công, có upstream, '
      'và branch có commit của riêng nó trên remote', () async {
    // Arrange: branch mới tách từ `main`, chưa có commit nào của riêng nó ⇒
    // nếu không có empty commit thì nó trỏ đúng vào tip của `main`.
    final dir = await clonedRepo();
    await _git(['checkout', '-q', '-b', 'feature/x'], dir);
    expect(await upstreamOf(dir, 'feature/x'), isNull,
        reason: 'Pre-condition: đây phải là branch CHƯA có upstream — đúng ca '
            'mà nút Publish được hiện ra.');
    expect(await _gitOut(['rev-list', '--count', 'main..feature/x'], dir), '0',
        reason: 'Pre-condition: branch chưa có commit riêng nào.');

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/x');

    // Assert
    expect(result.success, isTrue, reason: 'Output: ${result.output}');
    expect(result.output, 'Published feature/x to origin');
    expect(
      await upstreamOf(dir, 'feature/x'),
      'origin/feature/x',
      reason: 'Push phải dùng `-u`: không set upstream thì lần sau `git push` '
          'trần fail ("no upstream branch") và gate `hasUpstream` đọc sai.',
    );
    expect(
      await _gitOut(['log', '-1', '--format=%s', 'origin/feature/x'], dir),
      'publish new branch: feature/x',
      reason: 'Đây là lý do tồn tại của helper: branch phải có commit của '
          'RIÊNG nó trên GitHub, không chỉ trỏ ké vào tip của main.',
    );
    expect(
      await _gitOut(['rev-list', '--count', 'main..feature/x'], dir),
      '1',
      reason: 'Đúng 1 commit được tạo thêm — empty commit, không nhiều hơn.',
    );
  });

  test(
      'branch HIỆN TẠI đã có 2 commit riêng → vẫn thêm empty commit trên đầu '
      '(số commit đã có KHÔNG phải điều kiện)', () async {
    // Arrange: branch mới + 2 commit thật, và nó là branch đang checkout.
    final dir = await clonedRepo();
    await _git(['checkout', '-q', '-b', 'feature/y'], dir);
    await commits(dir, 2, 'work');
    expect(await _gitOut(['rev-list', '--count', 'main..feature/y'], dir), '2',
        reason: 'Pre-condition: 2 commit thật trước khi publish.');

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/y');

    // Assert
    expect(result.success, isTrue, reason: 'Output: ${result.output}');
    expect(
      await _gitOut(['rev-list', '--count', 'main..origin/feature/y'], dir),
      '3',
      reason: '2 commit thật + 1 empty commit. Điều kiện duy nhất là "branch có '
          'phải branch hiện tại", KHÔNG phải "branch đã có commit chưa" — nên '
          'đừng thêm nhánh bỏ commit khi đã có commit riêng. Ai muốn publish mà '
          'KHÔNG thêm commit thì đi đường `push -u` trần đã có sẵn '
          '(SimpleGitPushDialog / GitActionDialog._publishRepo).',
    );
    expect(
      await _gitOut(['log', '-1', '--format=%s', 'origin/feature/y'], dir),
      'publish new branch: feature/y',
    );
    expect(
      await _gitOut(['log', '--format=%s', 'main..origin/feature/y'], dir),
      contains('work-1'),
      reason: 'Công việc thật vẫn phải lên remote cùng lượt push.',
    );
  });

  test(
      'repo KHÔNG có remote `origin` → GitResult báo lỗi, KHÔNG throw '
      '(và empty commit đã tạo thì nằm lại, không rollback)', () async {
    // Arrange: `git init` thuần, chưa `git remote add` lần nào.
    final dir = await soloRepo();
    await _git(['checkout', '-q', '-b', 'feature/z'], dir);
    final before = await _gitOut(['rev-list', '--count', 'HEAD'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/z');

    // Assert
    expect(result.success, isFalse);
    expect(
      result.output,
      startsWith('Push failed:'),
      reason: 'Lỗi phải đi qua GitResult để dialog hiện được message; nếu nó '
          'throw thì `_publishBranch` (git_branch_dialog.dart:550) kẹt ở '
          '`_switching = true` và dialog không đóng được.',
    );
    expect(result.output.length, greaterThan('Push failed:'.length),
        reason: 'stderr thật của git phải được kèm theo, không nuốt mất.');
    expect(
      await _gitOut(['rev-list', '--count', 'HEAD'], dir),
      '${int.parse(before) + 1}',
      reason: 'Hành vi HIỆN TẠI: commit chạy trước push nên push fail vẫn để '
          'lại 1 empty commit trên branch. Chốt lại để lần sau ai thêm '
          'rollback thì phải đổi test một cách có ý thức.',
    );
  });

  /// Repo `git init` + `remote add origin`, CHƯA có commit nào (unborn HEAD).
  Future<String> unbornRepo(String name) async {
    final remotePath = p.join(tmp.path, '$name-remote.git');
    final dir = p.join(tmp.path, name);
    Directory(remotePath).createSync(recursive: true);
    Directory(dir).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);
    await _git(['init', '-q', '-b', 'main', '.'], dir);
    await _configIdentity(dir);
    await _git(['remote', 'add', 'origin', remotePath], dir);
    expect(await _gitOut(['rev-list', '--count', '--all'], dir), '0',
        reason: 'Pre-condition: repo hoàn toàn chưa có commit nào.');
    // Pre-condition về PROBE: `symbolic-ref --short HEAD` phải trả rc=0 + tên
    // branch ngay khi chưa có commit — đó là tính chất khiến hàm không cần
    // fail-open nữa. Nếu git đổi hành vi này thì cả 2 ca dưới phải xem lại.
    expect(await _gitOut(['symbolic-ref', '--short', 'HEAD'], dir), 'main',
        reason: 'Unborn HEAD vẫn là "đang ở trên branch main", chỉ là branch đó '
            'chưa có commit.');
    return dir;
  }

  test(
      'unborn HEAD + publish CHÍNH branch đó → tạo root commit rồi push thành '
      'công', () async {
    // Arrange: repo mới `git init`, chưa commit gì. Đây là ca CẦN commit — không
    // có commit thì chẳng có gì để push.
    final dir = await unbornRepo('unborn-same');

    // Act
    final result = await GitBranchService.publishBranch(dir, 'main');

    // Assert
    expect(result.success, isTrue, reason: 'Output: ${result.output}');
    expect(await _gitOut(['rev-list', '--count', '--all'], dir), '1',
        reason: 'Root commit phải được tạo: probe trả đúng tên branch nên đây là '
            'ca isCurrent thật, không phải một fallback.');
    expect(
      await _gitOut(['log', '-1', '--format=%s', 'origin/main'], dir),
      'publish new branch: main',
    );
    expect(await upstreamOf(dir, 'main'), 'origin/main');
  });

  test(
      'unborn HEAD + publish tên branch KHÁC → KHÔNG commit ở đâu cả, push fail '
      '(regression: bỏ fail-open theo probe)', () async {
    // Arrange: đứng trên `main` chưa có commit, gọi publish cho `feature/x`
    // (branch chưa tồn tại). Đây chính là ca tôi ĐO ĐƯỢC ở vòng 3 và cố ý KHÔNG
    // pin lúc đó: với probe `rev-parse --abbrev-ref HEAD` (rc=128 ở unborn) +
    // mệnh đề fail-open `head.exitCode != 0 ||`, hàm tạo một root commit trên
    // `main` — commit trên branch mà user KHÔNG hề nêu tên, đúng họ bug đã fix
    // trước đó. Pin lúc đó = khẳng định hành vi sai là đúng; nay hành vi đã đổi
    // nên ca này khẳng định điều ngược lại và trở thành guard thật.
    final dir = await unbornRepo('unborn-other');

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/x');

    // Assert
    expect(await _gitOut(['rev-list', '--count', '--all'], dir), '0',
        reason: 'KHÔNG được có commit nào ở bất cứ đâu: `feature/x` không phải '
            'branch đang checkout ⇒ không có quyền ghi vào HEAD. Đây là assert '
            'chính; nó đỏ ngay khi ai mang mệnh đề fail-open trở lại.',
    );
    expect(
      await Process.run('git', ['rev-parse', '--verify', 'main'],
              workingDirectory: dir)
          .then((r) => r.exitCode),
      isNot(0),
      reason: '`main` vẫn phải là unborn — không được "mọc" tip từ một lệnh '
          'publish cho branch khác.',
    );
    expect(result.success, isFalse);
    expect(result.output, startsWith('Push failed:'),
        reason: 'Không có ref `feature/x` để push ⇒ git từ chối; lỗi đi qua '
            'GitResult, không throw.');
  });

  test(
      'workingDir không phải git repo → "Push failed:", KHÔNG throw '
      '(KHÔNG còn chạy commit khi probe fail)', () async {
    // Arrange: thư mục trống, không `git init`.
    final dir = p.join(tmp.path, 'not-a-repo');
    Directory(dir).createSync(recursive: true);
    final probe = await Process.run(
      'git',
      ['rev-parse', '--is-inside-work-tree'],
      workingDirectory: dir,
    );
    expect(probe.exitCode, isNot(0),
        reason: 'Pre-condition: thư mục tạm này thật sự nằm ngoài mọi git repo '
            '— nếu systemTemp lại nằm trong một repo thì ca test này vô nghĩa.');

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/none');

    // Assert
    expect(result.success, isFalse);
    expect(
      result.output,
      startsWith('Push failed:'),
      reason: 'ĐÁNH ĐỔI ĐÃ NHẬN, đừng "sửa lại cho cụ thể": message kém cụ thể '
          'hơn một notch (trước đây là "Commit failed:") vì probe '
          '`symbolic-ref --short HEAD` rc=128 ở đây nay có nghĩa "HEAD không ở '
          'trên branch nào / không có repo" ⇒ KHÔNG chạy commit. Mang lại mệnh '
          'đề fail-open `head.exitCode != 0 ||` để lấy lại message cũ là mở lại '
          'đúng đường ghi commit vì một phép ĐỌC thất bại — xem ca unborn + '
          'publish tên branch KHÁC ở dưới.',
    );
    expect(result.output.length, greaterThan('Push failed:'.length),
        reason: 'stderr thật của git phải được kèm theo, không nuốt mất.');
  });

  test(
      'regression 🟠: publish branch KHÁC branch hiện tại → KHÔNG đẻ commit '
      'nào lên branch đang đứng, và branch đó vẫn lên tới remote', () async {
    // Arrange: đứng ở `main`, publish một branch khác — đúng đường mà nút
    // Publish ở `git_branch_dialog.dart:722-726` (nhánh `!isCurrent`) đi qua.
    //
    // Bug cũ (đã fix): `git commit` luôn ghi vào HEAD ⇒ empty commit rơi vào
    // `main` (bẩn branch người dùng đang đứng) trong khi `feature/other` lên
    // origin mà KHÔNG có commit riêng — hỏng cả hai đầu cùng lúc. Vì vậy ca này
    // assert CẢ HAI NỬA; chỉ assert `success` thì bug cũ cũng xanh.
    final dir = await clonedRepo();
    await _git(['branch', 'feature/other'], dir);
    expect(await _gitOut(['rev-parse', '--abbrev-ref', 'HEAD'], dir), 'main',
        reason: 'Pre-condition: HEAD vẫn ở `main`, không phải branch sắp '
            'publish.');
    final mainCountBefore = await _gitOut(['rev-list', '--count', 'main'], dir);
    final mainTipBefore = await _gitOut(['rev-parse', 'main'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/other');

    // Assert — nửa 1: branch đang đứng KHÔNG bị đụng tới.
    expect(await _gitOut(['rev-list', '--count', 'main'], dir), mainCountBefore,
        reason: 'Branch đang đứng không được phát sinh commit nào. Đếm trước/sau '
            'thay vì chỉ nhìn subject: subject giống nhau vẫn có thể là commit '
            'khác.');
    expect(await _gitOut(['rev-parse', 'main'], dir), mainTipBefore,
        reason: 'Tip của `main` phải nguyên si (cùng SHA), không chỉ "cùng số '
            'lượng".');

    // Assert — nửa 2: branch được publish thật sự lên tới remote, có upstream.
    expect(result.success, isTrue, reason: 'Output: ${result.output}');
    expect(result.output, 'Published feature/other to origin');
    expect(
      await _gitOut(['rev-parse', 'origin/feature/other'], dir),
      await _gitOut(['rev-parse', 'feature/other'], dir),
      reason: 'Ref trên origin phải trùng ref local — đây là toàn bộ việc mà '
          'nhánh không-phải-branch-hiện-tại được phép làm (lối của '
          'SimpleGitPushDialog: push -u trần, không empty commit).',
    );
    expect(await upstreamOf(dir, 'feature/other'), 'origin/feature/other');
  });

  test(
      'workingDir KHÔNG TỒN TẠI → THROW (không phải GitResult) — tiền đề của '
      'try/catch trong _publishBranch', () async {
    // Arrange: repo bị xoá / volume bị unmount. Khác hẳn ca "thư mục có thật
    // nhưng không phải repo" ở trên: ở đây `Process.run` không chạy nổi nên lỗi
    // KHÔNG đi qua exitCode.
    final gone = p.join(tmp.path, 'deleted-repo');
    expect(Directory(gone).existsSync(), isFalse);

    // Act + Assert
    await expectLater(
      GitBranchService.publishBranch(gone, 'feature/x'),
      throwsA(isA<ProcessException>()),
      reason: 'Đây là lý do `_publishBranch` (git_branch_dialog.dart:550) PHẢI '
          'có try/catch: không bắt thì `_switching`/`setDialogRunning(true)` '
          'nằm lại vĩnh viễn ⇒ nút đóng dialog bị disable, user phải kill app. '
          'Nếu sau này hàm này đổi sang trả GitResult cho ca này thì test đỏ và '
          'catch kia mới được phép bỏ.',
    );
  });

  test(
      'detached HEAD → không commit vào đâu cả, chỉ push ref '
      '(HEAD không ở trên branch nào ⇒ không có quyền ghi)', () async {
    // Arrange: repo có branch `feature/d` rồi detach HEAD. `symbolic-ref --short
    // HEAD` ở trạng thái này rc=128 (đo git 2.53) ⇒ không có tên branch nào để
    // so ⇒ nhánh commit bị bỏ qua. Ca này là lý do mệnh đề fail-open cũ nguy
    // hiểm: rc != 0 mà vẫn commit thì commit rơi vào một HEAD không branch nào
    // trỏ tới (mất sau `gc`).
    final dir = await clonedRepo();
    await _git(['branch', 'feature/d'], dir);
    await _git(['checkout', '-q', '--detach', 'HEAD'], dir);
    expect(
      await Process.run('git', ['symbolic-ref', '--short', 'HEAD'],
              workingDirectory: dir)
          .then((r) => r.exitCode),
      isNot(0),
      reason: 'Pre-condition đo CHÍNH probe mà publishBranch dùng: detached HEAD '
          '⇒ `symbolic-ref` rc != 0. Nếu git đổi hành vi này thì logic của '
          'publishBranch phải đổi theo — đỏ ở đây là tín hiệu đúng.',
    );
    final headBefore = await _gitOut(['rev-parse', 'HEAD'], dir);
    final mainBefore = await _gitOut(['rev-parse', 'main'], dir);
    final targetBefore = await _gitOut(['rev-parse', 'feature/d'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/d');

    // Assert
    expect(result.success, isTrue, reason: 'Output: ${result.output}');
    expect(await _gitOut(['rev-parse', 'HEAD'], dir), headBefore,
        reason: 'Detached HEAD không được nhận commit nào — commit ở đây tạo ra '
            'commit không branch nào trỏ tới, tức mất luôn sau `gc`.');
    expect(await _gitOut(['rev-parse', 'main'], dir), mainBefore);
    expect(await _gitOut(['rev-parse', 'feature/d'], dir), targetBefore,
        reason: 'Branch đích cũng không đổi: nhánh này chỉ push ref sẵn có.');
    expect(
      await _gitOut(['rev-parse', 'origin/feature/d'], dir),
      targetBefore,
      reason: 'Việc duy nhất phải xảy ra: ref lên tới origin. `push -u` từ '
          'detached HEAD là hợp lệ vì refname được nêu tường minh.',
    );
  });

  test(
      'regression 🟡: index có file đã `git add` → TỪ CHỐI publish kèm message, '
      'và KHÔNG đụng gì tới repo', () async {
    // Arrange: user stage một file rồi bấm Publish. `git commit --allow-empty`
    // KHÔNG có pathspec ⇒ nó commit nguyên index; "--allow-empty" chỉ nới điều
    // kiện "được phép rỗng", không có nghĩa "commit rỗng". Trước fix, work đang
    // dở của user bị commit dưới message 'publish new branch: …' rồi đẩy lên
    // origin, và staging area bị dọn sạch — im lặng.
    //
    // ĐÂY LÀ HÀNH VI MONG MUỐN (khác lần trước: ca này từng là characterization
    // "đang chốt"). Nam đã duyệt: thà từ chối kèm lý do còn hơn commit hộ.
    final dir = await clonedRepo();
    await _git(['checkout', '-q', '-b', 'feature/idx'], dir);
    File(p.join(dir, 'staged.txt')).writeAsStringSync('wip\n');
    await _git(['add', 'staged.txt'], dir);
    expect(await _gitOut(['diff', '--cached', '--name-only'], dir), 'staged.txt',
        reason: 'Pre-condition: file thật sự nằm trong index trước khi publish.');
    final commitsBefore = await _gitOut(['rev-list', '--count', 'HEAD'], dir);
    final statusBefore = await _gitOut(['status', '--porcelain'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'feature/idx');

    // Assert — từ chối, và nói rõ vì sao (user phải biết phải làm gì tiếp).
    expect(result.success, isFalse);
    expect(result.output, startsWith('Refusing to publish:'));
    expect(result.output, contains('feature/idx'),
        reason: 'Message phải nêu đúng message commit sẽ bị dùng, để user hiểu '
            'work của mình sắp bị dán nhãn gì.');

    // Assert — KHÔNG có tác dụng phụ nào. Đây là phần quan trọng nhất: một guard
    // "báo lỗi nhưng vẫn đã commit rồi" thì vô nghĩa.
    expect(await _gitOut(['rev-list', '--count', 'HEAD'], dir), commitsBefore,
        reason: 'Không được tạo commit nào.');
    expect(await _gitOut(['diff', '--cached', '--name-only'], dir), 'staged.txt',
        reason: 'File vẫn phải NẰM TRONG index — user không được mất staging '
            'area (hệ quả tệ nhất của bug cũ).');
    expect(await _gitOut(['status', '--porcelain'], dir), statusBefore,
        reason: 'Working tree + index y nguyên trạng thái trước khi bấm.');
  });

  test(
      'regression 🟡: đang merge dở VÀ index bẩn → TỪ CHỐI publish '
      '(ca này đi qua probe `diff --cached`, KHÔNG chứng minh gì về MERGE_HEAD)',
      () async {
    // ⚠ ĐỌC KỸ TRƯỚC KHI DÙNG CA NÀY LÀM BẰNG CHỨNG:
    // `merge --no-commit --no-ff` để lại MERGE_HEAD **và** một index khác HEAD
    // ⇒ `git diff --cached --quiet` rc=1 ⇒ ca này bị probe STAGED bắt trước.
    // Nó KHÔNG kiểm được cơ chế phát hiện merge: guard chỉ-`diff --cached` (tức
    // code trước fix 🟠 vòng 7) vẫn làm ca này xanh. Vòng 6 tôi đặt tên nó là
    // "MERGE_HEAD → TỪ CHỐI" — tên đó tạo niềm tin sai và đã bị reviewer bắt.
    // Ca canh MERGE_HEAD thật là ca NGAY DƯỚI (index sạch).
    // Giữ ca này vì trạng thái "vừa merge dở vừa có thay đổi staged" là trạng
    // thái thật, và nó chốt rằng khi CẢ HAI cùng xảy ra thì vẫn không có commit
    // nào được tạo.
    final dir = await clonedRepo();
    await _git(['checkout', '-q', '-b', 'feature/m'], dir);
    File(p.join(dir, 'side.txt')).writeAsStringSync('side\n');
    await _git(['add', '.'], dir);
    await _git(['commit', '-q', '-m', 'side work'], dir);
    await _git(['checkout', '-q', 'main'], dir);
    File(p.join(dir, 'main-only.txt')).writeAsStringSync('main\n');
    await _git(['add', '.'], dir);
    await _git(['commit', '-q', '-m', 'main work'], dir);
    await _git(['merge', '--no-commit', '--no-ff', 'feature/m'], dir);
    expect(File(p.join(dir, '.git', 'MERGE_HEAD')).existsSync(), isTrue,
        reason: 'Pre-condition: merge thật sự đang dở.');
    // Pre-condition thứ hai — chính là thứ vạch ra giới hạn của ca này: index
    // KHÁC HEAD nên probe staged đã đủ để chặn. Ghi tường minh để không ai lại
    // đọc ca này thành "guard merge có chạy".
    expect(
      await Process.run('git', ['diff', '--cached', '--quiet'],
              workingDirectory: dir)
          .then((r) => r.exitCode),
      1,
      reason: 'rc=1 ⇒ ca này bị probe `diff --cached` bắt trước, không cần tới '
          'probe MERGE_HEAD.',
    );
    final headBefore = await _gitOut(['rev-parse', 'HEAD'], dir);

    // Act: publish CHÍNH branch đang đứng (`main`) — nhánh có bước commit.
    final result = await GitBranchService.publishBranch(dir, 'main');

    // Assert
    expect(result.success, isFalse);
    expect(result.output, startsWith('Refusing to publish:'));
    expect(
      File(p.join(dir, '.git', 'MERGE_HEAD')).existsSync(),
      isTrue,
      reason: 'ĐIỂM KHÁC BIỆT so với ca staged-file: MERGE_HEAD còn nguyên nên '
          '`git merge --abort` vẫn dùng được. Nếu guard commit trước rồi mới báo '
          'lỗi thì merge bị hoàn tất và đường lùi của user biến mất.',
    );
    expect(await _gitOut(['rev-parse', 'HEAD'], dir), headBefore);
    expect(
      (await _gitOut(['rev-list', '--parents', '-1', 'HEAD'], dir))
          .split(RegExp(r'\s+'))
          .length,
      2,
      reason: 'HEAD phải còn đúng 1 parent (commit + 1 hash). Thành 3 token = '
          'merge đã bị commit hộ.',
    );
  });

  test(
      'regression 🟠: MERGE_HEAD còn nhưng index SẠCH (conflict resolve = giữ '
      'bản ours) → TỪ CHỐI publish theo nhánh MERGE, merge vẫn abort được',
      () async {
    // ── Đây là ca canh finding 🟠 vòng 7 ──
    // Tiền đề sai của guard cũ: "index bẩn ⇔ đang có việc dở". Sai, vì merge dở
    // nằm ở `.git/MERGE_HEAD`, KHÔNG ở index. Resolve conflict bằng cách giữ
    // nguyên bản của mình ⇒ index khớp HEAD ⇒ `diff --cached --quiet` rc=0 ⇒
    // guard chỉ-staged CHO QUA ⇒ `commit --allow-empty` HOÀN TẤT merge: HEAD
    // thành commit 2 cha, `git merge --abort` báo "There is no merge to abort",
    // rồi push lên origin. Reachable từ chính dialog này: `mergeIntoCurrent` /
    // `mergeIntoTarget` cố ý để conflict lại cho user tự resolve.
    final dir = await clonedRepo();
    final file = File(p.join(dir, 'conflict.txt'));

    // base commit chung
    file.writeAsStringSync('base\n');
    await _git(['add', '.'], dir);
    await _git(['commit', '-q', '-m', 'base'], dir);

    // branch `side` sửa cùng dòng
    await _git(['checkout', '-q', '-b', 'side'], dir);
    file.writeAsStringSync('side\n');
    await _git(['commit', '-q', '-am', 'side change'], dir);

    // về `main` sửa cùng dòng theo cách khác ⇒ merge sẽ conflict
    await _git(['checkout', '-q', 'main'], dir);
    file.writeAsStringSync('main\n');
    await _git(['commit', '-q', '-am', 'main change'], dir);
    final merge = await Process.run('git', ['merge', 'side'],
        workingDirectory: dir);
    expect(merge.exitCode, isNot(0),
        reason: 'Pre-condition: merge phải CONFLICT (không tự xong).');

    // resolve = giữ bản ours ⇒ nội dung y như HEAD
    file.writeAsStringSync('main\n');
    await _git(['add', 'conflict.txt'], dir);

    // Pre-condition kép — chính là điểm mà guard cũ lọt:
    expect(File(p.join(dir, '.git', 'MERGE_HEAD')).existsSync(), isTrue,
        reason: 'Merge vẫn đang dở.');
    expect(
      await Process.run('git', ['diff', '--cached', '--quiet'],
              workingDirectory: dir)
          .then((r) => r.exitCode),
      0,
      reason: 'INDEX SẠCH (rc=0) — nếu ca này rc=1 thì nó lại bị probe staged '
          'bắt và không còn canh được probe MERGE_HEAD nữa. Đỏ ở đây nghĩa là '
          'fixture đã trượt khỏi ý định, KHÔNG phải code sai.',
    );
    final headBefore = await _gitOut(['rev-parse', 'HEAD'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'main');

    // Assert — phải là nhánh MERGE, không phải nhánh staged.
    expect(result.success, isFalse);
    expect(result.output, startsWith('Refusing to publish:'));
    expect(result.output, contains('middle of a merge'),
        reason: 'Message phải nói đúng nguyên nhân: đang merge dở.');
    expect(result.output, isNot(contains('staged changes')),
        reason: 'Khuyên "unstage" ở đây là chỉ sai đường — index đang sạch, thứ '
            'cần làm là finish/abort merge.');

    // Assert — đường lùi của user còn nguyên (giá trị thật của guard này).
    expect(File(p.join(dir, '.git', 'MERGE_HEAD')).existsSync(), isTrue,
        reason: '`git merge --abort` phải còn dùng được.');
    expect(await _gitOut(['rev-parse', 'HEAD'], dir), headBefore);
    expect(
      (await _gitOut(['rev-list', '--parents', '-1', 'HEAD'], dir))
          .split(RegExp(r'\s+'))
          .length,
      2,
      reason: 'HEAD còn đúng 1 parent. Thành 3 token = merge đã bị hoàn tất hộ — '
          'đúng hậu quả của finding 🟠.',
    );
  });

  /// Repo có `conflict.txt` với 3 mốc: base → branch [other] đổi 1 dòng →
  /// `main` đổi cùng dòng theo cách khác. Dùng chung cho ca cherry-pick và
  /// revert: cả hai cần một thay đổi CHỒNG NHAU để tạo conflict thật.
  Future<({String dir, File file})> divergedRepo(String other) async {
    final dir = await clonedRepo();
    final file = File(p.join(dir, 'conflict.txt'));
    file.writeAsStringSync('base\n');
    await _git(['add', '.'], dir);
    await _git(['commit', '-q', '-m', 'base'], dir);
    await _git(['checkout', '-q', '-b', other], dir);
    file.writeAsStringSync('$other\n');
    await _git(['commit', '-q', '-am', '$other change'], dir);
    await _git(['checkout', '-q', 'main'], dir);
    file.writeAsStringSync('main\n');
    await _git(['commit', '-q', '-am', 'main change'], dir);
    return (dir: dir, file: file);
  }

  /// rc của `git diff --cached --quiet` (không fail test khi non-zero).
  Future<int> stagedProbeRc(String dir) => Process.run(
        'git',
        ['diff', '--cached', '--quiet'],
        workingDirectory: dir,
      ).then((r) => r.exitCode);

  test(
      'regression 🟠: CHERRY_PICK_HEAD còn nhưng index SẠCH → TỪ CHỐI publish '
      'theo nhánh CHERRY-PICK (phân loại đúng thành viên, không phải "a merge")',
      () async {
    // Cùng cơ chế với ca MERGE_HEAD: việc dở nằm ở ref, không ở index. Khác ở
    // chỗ nó KHÔNG tạo commit 2-parent nên history ít méo hơn — nhưng
    // `git cherry-pick --abort` vẫn mất tác dụng, và đó là đường lùi của user.
    final repo = await divergedRepo('pick-src');
    final dir = repo.dir;
    final pick = await Process.run('git', ['cherry-pick', 'pick-src'],
        workingDirectory: dir);
    expect(pick.exitCode, isNot(0),
        reason: 'Pre-condition: cherry-pick phải CONFLICT.');

    // resolve = giữ bản ours ⇒ index khớp HEAD
    repo.file.writeAsStringSync('main\n');
    await _git(['add', 'conflict.txt'], dir);

    // Pre-condition kép — điểm mà cả 2 probe cũ lọt:
    expect(File(p.join(dir, '.git', 'CHERRY_PICK_HEAD')).existsSync(), isTrue);
    expect(await stagedProbeRc(dir), 0,
        reason: 'INDEX SẠCH — nếu rc=1 thì ca này bị probe staged bắt và không '
            'còn canh được ref CHERRY_PICK_HEAD. Đỏ ở đây = fixture trượt khỏi '
            'ý định, KHÔNG phải code sai.');
    final headBefore = await _gitOut(['rev-parse', 'HEAD'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'main');

    // Assert
    expect(result.success, isFalse);
    expect(result.output, contains('a cherry-pick'));
    expect(result.output, isNot(contains('a merge')),
        reason: 'Phân loại phải đúng THÀNH VIÊN: nói "a merge" ở đây là chỉ sai '
            'lệnh cần chạy (abort của cherry-pick khác của merge). Assert này là '
            'thứ phân biệt "guard chạy" với "guard chạy ĐÚNG nhánh".');
    expect(File(p.join(dir, '.git', 'CHERRY_PICK_HEAD')).existsSync(), isTrue,
        reason: '`git cherry-pick --abort` phải còn dùng được.');
    expect(await _gitOut(['rev-parse', 'HEAD'], dir), headBefore);
  });

  test(
      'regression 🟠: REVERT_HEAD còn nhưng index SẠCH → TỪ CHỐI publish theo '
      'nhánh REVERT', () async {
    // Thành viên thứ ba của cùng họ. Fixture: revert một commit mà thay đổi của
    // nó đã bị commit sau ghi đè ⇒ revert conflict.
    final repo = await divergedRepo('rev-src');
    final dir = repo.dir;
    // `main change` là commit HEAD; revert `base`→? cần commit có thay đổi bị
    // ghi đè: revert chính `main change`'s parent không conflict. Dùng commit
    // 'base' (đặt conflict.txt = base) — nay file là 'main' ⇒ revert conflict.
    final baseSha = await _gitOut(['rev-parse', 'HEAD~1'], dir);
    final revert = await Process.run(
        'git', ['revert', '--no-edit', baseSha], workingDirectory: dir);
    expect(revert.exitCode, isNot(0),
        reason: 'Pre-condition: revert phải CONFLICT.');

    // resolve = giữ bản ours
    repo.file.writeAsStringSync('main\n');
    await _git(['add', 'conflict.txt'], dir);

    expect(File(p.join(dir, '.git', 'REVERT_HEAD')).existsSync(), isTrue);
    expect(await stagedProbeRc(dir), 0,
        reason: 'INDEX SẠCH — xem lý do ở ca cherry-pick.');
    final headBefore = await _gitOut(['rev-parse', 'HEAD'], dir);

    // Act
    final result = await GitBranchService.publishBranch(dir, 'main');

    // Assert
    expect(result.success, isFalse);
    expect(result.output, contains('a revert'));
    expect(result.output, isNot(contains('a merge')));
    expect(File(p.join(dir, '.git', 'REVERT_HEAD')).existsSync(), isTrue);
    expect(await _gitOut(['rev-parse', 'HEAD'], dir), headBefore);
  });

  test(
      'rebase đang dở → KHÔNG commit gì (bị chặn bởi probe `symbolic-ref`, '
      'KHÔNG bởi vòng lặp in-progress)', () async {
    // ⚠ Ca này khoá một LẬP LUẬN, không phải một dòng code: rebase KHÔNG có mặt
    // trong `inProgressRefs` và đó là CHỦ Ý — rebase dừng lại với HEAD detached
    // nên `symbolic-ref --short HEAD` rc=128 và luồng không bao giờ tới bước
    // commit. Đo được (git 2.53): rebase-with-conflict ⇒ `.git/rebase-merge`
    // tồn tại, `symbolic-ref` rc=128.
    // ⇒ Thấy rebase thiếu trong danh sách thì ĐỪNG thêm probe: đọc ca này trước.
    // Nếu sau này ai làm `symbolic-ref` fail-open (rc != 0 ⇒ vẫn commit) thì
    // chính ca này đỏ — đó là lý do nó tồn tại.
    final repo = await divergedRepo('feature/rb');
    final dir = repo.dir;
    await _git(['checkout', '-q', 'feature/rb'], dir);
    final rebase =
        await Process.run('git', ['rebase', 'main'], workingDirectory: dir);
    expect(rebase.exitCode, isNot(0),
        reason: 'Pre-condition: rebase phải CONFLICT.');
    expect(
      await Process.run('git', ['symbolic-ref', '--short', 'HEAD'],
              workingDirectory: dir)
          .then((r) => r.exitCode),
      128,
      reason: 'Pre-condition CỐT LÕI: HEAD detached trong lúc rebase — đây là '
          'toàn bộ lý do không cần probe rebase.',
    );
    final countBefore = await _gitOut(['rev-list', '--count', '--all'], dir);
    final headBefore = await _gitOut(['rev-parse', 'HEAD'], dir);

    // Act
    await GitBranchService.publishBranch(dir, 'feature/rb');

    // Assert: không quan tâm success (push có thể thành công vì ref tồn tại);
    // điều phải đúng là KHÔNG có commit nào sinh ra.
    expect(await _gitOut(['rev-list', '--count', '--all'], dir), countBefore,
        reason: 'Không được tạo commit nào trong lúc rebase dở.');
    expect(await _gitOut(['rev-parse', 'HEAD'], dir), headBefore,
        reason: 'Commit vào detached HEAD giữa rebase = commit không branch nào '
            'trỏ tới, và làm `git rebase --continue` lệch.');
  });
}
