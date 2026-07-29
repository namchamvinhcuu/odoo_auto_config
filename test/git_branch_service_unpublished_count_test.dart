// Test cho `GitBranchService.loadUnpublishedCount` — `git rev-list --count HEAD
// --not --remotes`, tức "số commit trên HEAD chưa có trên remote NÀO".
//
// Vì sao cần: branch chưa publish có `ahead = 0` (đúng — không có upstream để mà
// "ahead"), nên chỉ nhìn ahead thì một branch mới toanh đầy commit trông như
// sạch. Con số này là thứ phân biệt "cần Publish" với "không có gì để đẩy".
//
// Hành vi git đã VERIFY trên máy này (git 2.53.0):
//   - repo KHÔNG có remote nào → rc=0, đếm hết commit (khác `@{upstream}` là
//     fatal) — đó chính là điểm mạnh của `--not --remotes`
//   - không phải repo → rc=128 ⇒ helper trả 0
//   - branch CÓ upstream nhưng 2 commit chưa push → helper vẫn trả 2; việc bỏ
//     qua con số này khi có upstream là trách nhiệm của caller (provider)

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
  late String remotePath;
  late String localPath;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('git_unpublished_');
    remotePath = p.join(tmp.path, 'remote.git');
    localPath = p.join(tmp.path, 'local');

    Directory(remotePath).createSync(recursive: true);
    await _git(['init', '--bare', '-b', 'main', remotePath], tmp.path);
    await _git(['clone', remotePath, localPath], tmp.path);
    await _configIdentity(localPath);
    File(p.join(localPath, 'README.md')).writeAsStringSync('v1\n');
    await _git(['add', '.'], localPath);
    await _git(['commit', '-m', 'initial'], localPath);
    await _git(['push', '-u', 'origin', 'main'], localPath);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Tạo [count] commit trong [cwd].
  Future<void> commits(String cwd, int count, String prefix) async {
    for (var i = 0; i < count; i++) {
      File(p.join(cwd, '$prefix-$i.txt')).writeAsStringSync('$prefix$i\n');
      await _git(['add', '.'], cwd);
      await _git(['commit', '-m', '$prefix-$i'], cwd);
    }
  }

  test('branch mới (checkout -b) + 3 commit chưa push → 3', () async {
    // Arrange
    await _git(['checkout', '-q', '-b', 'feature/x'], localPath);
    await commits(localPath, 3, 'new');

    // Act
    final count = await GitBranchService.loadUnpublishedCount(localPath);

    // Assert
    expect(count, 3);
  });

  test('branch đã push hết → 0', () async {
    // Act
    final count = await GitBranchService.loadUnpublishedCount(localPath);

    // Assert
    expect(count, 0);
  });

  test('branch mới sau khi push -u → về 0', () async {
    // Arrange
    await _git(['checkout', '-q', '-b', 'feature/y'], localPath);
    await commits(localPath, 2, 'pub');
    expect(await GitBranchService.loadUnpublishedCount(localPath), 2,
        reason: 'trước publish phải là 2, nếu không fixture sai');
    await _git(['push', '-q', '-u', 'origin', 'feature/y'], localPath);

    // Act
    final count = await GitBranchService.loadUnpublishedCount(localPath);

    // Assert
    expect(count, 0);
  });

  test(
      'repo KHÔNG có remote nào + 2 commit → 2 (không fail — điểm mạnh của '
      '--not --remotes so với @{upstream})', () async {
    // Arrange
    final solo = p.join(tmp.path, 'solo');
    Directory(solo).createSync(recursive: true);
    await _git(['init', '-q', '-b', 'main', '.'], solo);
    await _configIdentity(solo);
    await commits(solo, 2, 'solo');

    // Act
    final count = await GitBranchService.loadUnpublishedCount(solo);

    // Assert
    expect(count, 2);
  });

  test(
      'branch CÓ upstream + 2 commit chưa push → 2 (helper đếm thô; lọc theo '
      'hasUpstream là việc của caller)', () async {
    // Arrange
    await commits(localPath, 2, 'ahead');

    // Act
    final count = await GitBranchService.loadUnpublishedCount(localPath);

    // Assert — con số này KHÁC 0 chính là lý do provider phải gate theo
    // hasUpstream; xem other_projects_unpublished_count_test.dart.
    expect(count, 2);
  });

  test('thư mục KHÔNG phải git repo → 0, không throw', () async {
    // Arrange
    final plain = p.join(tmp.path, 'plain');
    Directory(plain).createSync(recursive: true);

    // Act
    final count = await GitBranchService.loadUnpublishedCount(plain);

    // Assert
    expect(count, 0);
  });
}
