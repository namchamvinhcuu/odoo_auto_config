// Test cho `GitBranchService.loadLocalStatus` — helper public GỘP
// `rev-parse --abbrev-ref HEAD` + `status --porcelain`.
//
// Vì sao helper này cần test riêng: phép đếm "changed files" trước refactor có
// **3 bản** (loadBranches / other_projects_provider / odoo_workspace_dialog) với
// 3 biểu thức tách dòng khác nhau, chỉ 2 bản có test → bản thứ ba trôi tự do.
// Nay còn 1 bản duy nhất, và đây là guard của nó (mutant G3: đổi cách tách dòng
// / bỏ `.where(isNotEmpty)` phải ĐỎ).
//
// Dùng git fixture THẬT (Process.run thật, cần `git` trong PATH) — helper gọi
// `runGit` trực tiếp, không inject được.
//
// Hành vi git đã VERIFY trên máy này (git 2.53.0) thay vì đoán:
//   - detached HEAD  → `rev-parse --abbrev-ref HEAD` in ra literal `HEAD` (rc 0)
//   - không phải repo → cả rev-parse và status rc=128 → helper trả ('', 0)
//   - file có khoảng trắng → porcelain quote tên nhưng vẫn là MỘT dòng

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
  late String repoPath;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('git_local_status_');
    repoPath = p.join(tmp.path, 'repo');
    Directory(repoPath).createSync(recursive: true);
    await _git(['init', '-q', '-b', 'main', '.'], repoPath);
    await _configIdentity(repoPath);
    File(p.join(repoPath, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], repoPath);
    await _git(['commit', '-m', 'initial'], repoPath);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('tree sạch → branch = tên branch hiện tại, changedFiles = 0', () async {
    // Act
    final status = await GitBranchService.loadLocalStatus(repoPath);

    // Assert
    expect(status.branch, 'main');
    expect(status.changedFiles, 0,
        reason: 'tree sạch phải là 0, không phải số dư từ lần đọc trước');
  });

  test('branch khác main → trả đúng tên branch có dấu "/"', () async {
    // Arrange
    await _git(['checkout', '-q', '-b', 'feature/x'], repoPath);

    // Act
    final status = await GitBranchService.loadLocalStatus(repoPath);

    // Assert
    expect(status.branch, 'feature/x');
  });

  test(
      '3 thay đổi ở 3 trạng thái khác nhau (modified / staged / untracked có '
      'khoảng trắng trong tên) → changedFiles = 3', () async {
    // Arrange — đúng chỗ 3 bản đếm cũ từng khác nhau: porcelain quote tên file
    // có khoảng trắng nhưng vẫn là 1 dòng; staged và unstaged đều tính.
    File(p.join(repoPath, 'README.md')).writeAsStringSync('v1\nmodified\n');
    File(p.join(repoPath, 'a file with spaces.txt')).writeAsStringSync('x\n');
    File(p.join(repoPath, 'staged.txt')).writeAsStringSync('s\n');
    await _git(['add', 'staged.txt'], repoPath);

    // Act
    final status = await GitBranchService.loadLocalStatus(repoPath);

    // Assert
    expect(status.changedFiles, 3);
    expect(status.branch, 'main');
  });

  test('1 file đổi duy nhất → changedFiles = 1 (không đếm dòng rỗng cuối)',
      () async {
    // Arrange — porcelain kết thúc bằng '\n', cách tách dòng thô `split('\n')`
    // sẽ ra 2 phần tử (1 rỗng) → đây là ca chặn mutant bỏ `.where(isNotEmpty)`.
    File(p.join(repoPath, 'only.txt')).writeAsStringSync('one\n');

    // Act
    final status = await GitBranchService.loadLocalStatus(repoPath);

    // Assert
    expect(status.changedFiles, 1);
  });

  test('detached HEAD → branch = "HEAD" (literal git trả về), không throw',
      () async {
    // Arrange
    await _git(['checkout', '-q', '--detach', 'HEAD'], repoPath);

    // Act
    final status = await GitBranchService.loadLocalStatus(repoPath);

    // Assert — verify thực tế: git 2.53 in ra literal 'HEAD', không phải rỗng.
    expect(status.branch, 'HEAD');
    expect(status.changedFiles, 0);
  });

  test('thư mục KHÔNG phải git repo → ("", 0) và không throw', () async {
    // Arrange
    final plain = p.join(tmp.path, 'plain');
    Directory(plain).createSync(recursive: true);
    File(p.join(plain, 'file.txt')).writeAsStringSync('x\n');

    // Act
    final status = await GitBranchService.loadLocalStatus(plain);

    // Assert
    expect(status.branch, '');
    expect(status.changedFiles, 0);
  });
}
