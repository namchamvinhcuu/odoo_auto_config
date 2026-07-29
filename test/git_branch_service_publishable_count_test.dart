// Test cho `GitBranchService.loadPublishableCount` — hàm gộp GATE + ĐẾM của
// affordance Publish, dùng chung cho cả 2 surface (card Other Projects và tile
// Odoo Workspace).
//
// ── Vì sao file này tồn tại (gap G7 trong [[Architecture/Git-Status-Paths]]) ──
// Rule "repo không có remote nào ⇒ đừng mời Publish" trước đây được viết TẠI CHỖ
// trong `other_projects_provider.dart` (`await getRemoteUrl(path) != null`), nằm
// bên trong một `AsyncNotifier` chỉ chạy được khi có `StorageService` +
// filesystem thật ⇒ **không có test nào canh nó**: xoá dòng đó thì mọi test vẫn
// xanh, và hệ quả là card hiện badge = TOÀN BỘ history + một nút Publish luôn
// fail (`'origin' does not appear to be a git repository`).
// Nay rule sống trong một static method có input là `workingDir` ⇒ quan sát được
// bằng git fixture thật. Mutant M11 (xoá đúng dòng đó) phải làm test này đỏ.
//
// ── Cách test đọc input GIỐNG caller thật, không hardcode ──
// `hasUpstream` + `branch` được đo TỪ REPO bằng chính 2 helper mà 2 caller dùng
// (`loadLocalStatus` / `loadUpstreamDivergence`), thay vì truyền literal. Nhờ vậy
// ca "detached HEAD" là detached HEAD THẬT (git trả branch == 'HEAD'), ca "chưa
// commit" là unborn branch THẬT (git rev-parse fail ⇒ branch == ''), chứ không
// phải test lại chính giả định của người viết test.
//
// Không dùng widget/`runAsync`: đây là unit test thuần chạy `Process.run` git.

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

/// Đảm bảo commit không bị chặn bởi global hooks / thiếu user.* config.
Future<void> _configIdentity(String cwd) async {
  await _git(['config', 'user.email', 'test@example.com'], cwd);
  await _git(['config', 'user.name', 'Test'], cwd);
  await _git(['config', 'commit.gpgsign', 'false'], cwd);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('git_publishable_');
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

  /// Gọi `loadPublishableCount` với input ĐO TỪ REPO — đúng như 2 caller thật:
  /// `other_projects_provider` (`local.branch` + `divergence.hasUpstream`) và
  /// `_OdooWorkspaceDialogState._applyStatus` (`repo.branch` + cùng divergence).
  Future<int> publishableFor(String dir) async {
    final local = await GitBranchService.loadLocalStatus(dir);
    final divergence = await GitBranchService.loadUpstreamDivergence(dir);
    return GitBranchService.loadPublishableCount(
      dir,
      hasUpstream: divergence.hasUpstream,
      branch: local.branch,
    );
  }

  /// Repo standalone (`git init`, KHÔNG remote) với [commitCount] commit.
  Future<String> soloRepo(int commitCount) async {
    final dir = p.join(tmp.path, 'solo');
    Directory(dir).createSync(recursive: true);
    await _git(['init', '-q', '-b', 'main', '.'], dir);
    await _configIdentity(dir);
    if (commitCount > 0) await commits(dir, commitCount, 'solo');
    return dir;
  }

  /// Clone từ bare remote, branch `main` đã push.
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

  test(
      'repo có commit nhưng KHÔNG có remote nào → 0 '
      '(gap G7: Publish sẽ fail, badge sẽ hiện cả history)', () async {
    // Arrange: `git init` + 2 commit, KHÔNG `git remote add` lần nào.
    final dir = await soloRepo(2);
    // Pre-condition: bản thân bộ đếm thô KHÁC 0 ở đây — `--not --remotes` không
    // có remote nào để loại nên nó đếm toàn bộ history. Nếu không có dòng này,
    // ca test dưới có thể xanh chỉ vì repo rỗng (xanh giả).
    expect(
      await GitBranchService.loadUnpublishedCount(dir),
      2,
      reason: 'Bộ đếm thô phải trả 2 — nếu nó trả 0 thì assert chính bên dưới '
          'không chứng minh được gate remote có chạy.',
    );

    // Act
    final count = await publishableFor(dir);

    // Assert
    expect(
      count,
      0,
      reason: 'Không có `origin` ⇒ `git push -u origin <branch>` fail với '
          '"\'origin\' does not appear to be a git repository". Con số chỉ đáng '
          'hiện khi hành động nó mời gọi có thể thành công.',
    );
  });

  test('repo có remote, branch chưa publish, 2 commit → 2', () async {
    // Arrange: branch mới toanh (chưa có trên remote) + 2 commit.
    final dir = await clonedRepo();
    await _git(['checkout', '-q', '-b', 'feature/x'], dir);
    await commits(dir, 2, 'new');

    // Act
    final count = await publishableFor(dir);

    // Assert
    expect(count, 2,
        reason: 'Đúng ca cần Publish: có remote, branch chưa lên remote, có '
            'commit để đẩy.');
  });

  test('branch ĐÃ có upstream → 0 (không đếm dù có commit chưa push)', () async {
    // Arrange: `main` đã `push -u` trong fixture, thêm 2 commit chưa push.
    final dir = await clonedRepo();
    await commits(dir, 2, 'ahead');
    // Pre-condition: bộ đếm thô vẫn thấy 2 — nên số 0 ở dưới là do GATE, không
    // phải do repo sạch.
    expect(await GitBranchService.loadUnpublishedCount(dir), 2,
        reason: 'Bộ đếm thô đếm cả commit chưa push của branch có upstream.');

    // Act
    final count = await publishableFor(dir);

    // Assert
    expect(
      count,
      0,
      reason: 'Có upstream ⇒ hành động đúng là Push (badge ahead), không phải '
          'Publish. Hai affordance cùng hiện là trạng thái vô nghĩa.',
    );
  });

  test('detached HEAD → 0', () async {
    // Arrange: repo có remote + 2 commit, rồi detach vào HEAD~1.
    final dir = await clonedRepo();
    await commits(dir, 2, 'det');
    await _git(['checkout', '-q', '--detach', 'HEAD~1'], dir);
    // Pre-condition: git thật báo branch == 'HEAD' (không phải rỗng, không phải
    // tên branch) — đây chính là input mà rule `branch != 'HEAD'` chặn.
    expect((await GitBranchService.loadLocalStatus(dir)).branch, 'HEAD',
        reason: 'Nếu git đổi cách báo detached HEAD thì rule của predicate cũng '
            'phải đổi theo — fail ở đây là tín hiệu đúng.');

    // Act
    final count = await publishableFor(dir);

    // Assert
    expect(count, 0,
        reason: '`push -u origin HEAD` bị git từ chối vì không phải full '
            'refname ⇒ không có gì để mời.');
  });

  test('repo `git init` chưa có commit nào → 0, không throw', () async {
    // Arrange: unborn branch — `rev-parse --abbrev-ref HEAD` fail ⇒ branch ''.
    final dir = await soloRepo(0);
    expect((await GitBranchService.loadLocalStatus(dir)).branch, '',
        reason: 'Pre-condition: đây là ca branch RỖNG thật, không phải tên '
            'branch bịa ra.');

    // Act
    final count = await publishableFor(dir);

    // Assert
    expect(count, 0);
  });
}
