// Test cho `other_projects_provider.loadBranchStatus` — hai map MỚI của yêu cầu
// #2 (Publish cho branch chưa publish): `hasUpstream` + `unpublishedCount`.
//
// Điểm phải bảo vệ:
//  1. Branch CÓ upstream → `unpublishedCount = 0` DÙ `rev-list --not --remotes`
//     trả số > 0. Ở đó chỉ số ahead có nghĩa, và nút đúng là Push chứ không phải
//     Publish. Fixture cố tình để 2 commit chưa push để hai con số KHÁC nhau —
//     nếu bỏ điều kiện gate (luôn đếm) thì test này ĐỎ.
//  2. Branch KHÔNG upstream → `unpublishedCount` = số commit thật,
//     `aheadCount = 0`, `hasUpstream = false`.
//  3. Không stale: gọi 2 lần trên CÙNG path/CÙNG container qua một lần switch
//     branch → cả hai map phải cập nhật, không giữ số của branch trước (đúng lớp
//     bug đã ship với `behindCount` và `aheadCount`).
//
// Dùng git fixture THẬT (provider gọi Process.run thật, không inject được).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_auto_config/providers/other_projects_provider.dart';
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
    tmp = Directory.systemTemp.createTempSync('other_projects_unpublished_');
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

  /// Dựng notifier trên một ProviderContainer MỚI (fresh state mỗi test) kèm hàm
  /// đọc state. Test stale gọi hàm này MỘT lần rồi dùng lại object trả về, để cả
  /// hai lần `loadBranchStatus` chạy trên cùng container — đúng như UI thật.
  Future<({OtherProjectsNotifier notifier, OtherProjectsState? Function() read})>
      newNotifier() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(otherProjectsProvider.future);
    return (
      notifier: container.read(otherProjectsProvider.notifier),
      read: () => container.read(otherProjectsProvider).valueOrNull,
    );
  }

  test(
      'branch CÓ upstream + 2 commit chưa push → hasUpstream=true, '
      'unpublishedCount=0 (KHÔNG đếm), aheadCount=2', () async {
    // Arrange — hai phép đếm cho ra số KHÁC nhau ở đây: `--not --remotes` = 2,
    // nhưng đúng nghiệp vụ là 0 vì repo này cần Push, không phải Publish.
    await commits(localPath, 2, 'ahead');
    final ctx = await newNotifier();

    // Act
    await ctx.notifier.loadBranchStatus(localPath);
    final state = ctx.read();

    // Assert
    expect(state?.hasUpstream[localPath], isTrue);
    expect(state?.unpublishedCount[localPath], 0,
        reason: 'có upstream thì chỉ ahead có nghĩa; đếm unpublished ở đây sẽ '
            'hiện badge Publish sai trên repo chỉ cần Push');
    expect(state?.aheadCount[localPath], 2);
  });

  test(
      'branch mới chưa publish + 2 commit → hasUpstream=false, '
      'unpublishedCount=2, aheadCount=0', () async {
    // Arrange
    await _git(['checkout', '-q', '-b', 'feature/x'], localPath);
    await commits(localPath, 2, 'new');
    final ctx = await newNotifier();

    // Act
    await ctx.notifier.loadBranchStatus(localPath);
    final state = ctx.read();

    // Assert
    expect(state?.hasUpstream[localPath], isFalse);
    expect(state?.unpublishedCount[localPath], 2);
    expect(state?.aheadCount[localPath], 0,
        reason: 'không có upstream thì không thể "ahead" — 0 là giá trị thật');
    expect(state?.branches[localPath], 'feature/x');
  });

  // ── Regression cho finding 🟠 của flutter-reviewer (vòng 2) ───────────────
  // Gate `hasUpstream ? 0 : count` để lọt hai ca mà `hasUpstream=false` KHÔNG
  // đồng nghĩa "publish được": không có remote nào, và detached HEAD. Ở đó số
  // đếm là toàn bộ history — badge hiện con số user không làm gì được, và nút
  // Publish chạy là fail (`'origin' does not appear to be a git repository`
  // rc=128 / `not a full refname` rc=1). Fix: chỉ đếm khi THẬT SỰ publishable.

  test(
      'regression 🟠: repo KHÔNG có remote nào + 2 commit → unpublishedCount = 0 '
      '(Publish sẽ fail vì không có origin ⇒ không được hiện badge)', () async {
    // Arrange — repo độc lập, `git init`, không add remote.
    final solo = p.join(tmp.path, 'solo');
    Directory(solo).createSync(recursive: true);
    await _git(['init', '-q', '-b', 'main', '.'], solo);
    await _configIdentity(solo);
    await commits(solo, 2, 'solo');
    // Pre-condition: phép đếm thô CÓ trả 2 ở đây (trước fix badge hiện "2") ⇒
    // test này chỉ xanh nếu provider tự lọc, không phải vì git trả 0.
    final raw = await Process.run(
      'git',
      ['rev-list', '--count', 'HEAD', '--not', '--remotes'],
      workingDirectory: solo,
    );
    expect((raw.stdout as String).trim(), '2',
        reason: 'fixture sai: git phải đếm 2 ở đây mới đo được cái gate');
    final ctx = await newNotifier();

    // Act
    await ctx.notifier.loadBranchStatus(solo);
    final state = ctx.read();

    // Assert
    expect(state?.hasUpstream[solo], isFalse);
    expect(state?.unpublishedCount[solo], 0,
        reason: 'không có origin ⇒ không publish được ⇒ badge phải im');
    expect(state?.branches[solo], 'main',
        reason: 'vẫn phải đọc được branch (gate không được làm rơi field khác)');
  });

  test(
      'regression 🟠: detached HEAD (repo CÓ remote, có commit chưa push) → '
      'unpublishedCount = 0 (không có tên branch để publish)', () async {
    // Arrange
    await commits(localPath, 2, 'det');
    await _git(['checkout', '-q', '--detach', 'HEAD'], localPath);
    final ctx = await newNotifier();

    // Act
    await ctx.notifier.loadBranchStatus(localPath);
    final state = ctx.read();

    // Assert
    expect(state?.branches[localPath], 'HEAD',
        reason: 'git trả literal HEAD khi detached — đó là dấu hiệu để gate');
    expect(state?.hasUpstream[localPath], isFalse);
    expect(state?.unpublishedCount[localPath], 0,
        reason: 'push -u origin HEAD bị git từ chối (not a full refname) ⇒ '
            'không được mời user Publish');
  });

  test(
      'regression 🟠: fix KHÔNG được sửa quá tay — branch mới CÓ remote vẫn đếm '
      'đủ (ca dương phải sống)', () async {
    // Arrange — repo clone (có origin) + branch mới 3 commit chưa push.
    await _git(['checkout', '-q', '-b', 'feature/publishable'], localPath);
    await commits(localPath, 3, 'pub');
    final ctx = await newNotifier();

    // Act
    await ctx.notifier.loadBranchStatus(localPath);
    final state = ctx.read();

    // Assert
    expect(state?.hasUpstream[localPath], isFalse);
    expect(state?.unpublishedCount[localPath], 3,
        reason: 'đây là ca DUY NHẤT nút Publish có nghĩa — siết gate quá tay sẽ '
            'giết luôn feature #2');
  });

  test(
      'không stale: sau khi switch từ branch có upstream sang branch mới, '
      'unpublishedCount + hasUpstream đều cập nhật', () async {
    // Arrange — lần 1 trên main (có upstream, đã push hết).
    final ctx = await newNotifier();
    await ctx.notifier.loadBranchStatus(localPath);
    expect(ctx.read()?.hasUpstream[localPath], isTrue);
    expect(ctx.read()?.unpublishedCount[localPath], 0);

    // Act — switch sang branch chưa publish rồi gọi LẠI trên cùng path/container.
    await _git(['checkout', '-q', '-b', 'feature/z'], localPath);
    await commits(localPath, 2, 'sw');
    await ctx.notifier.loadBranchStatus(localPath);

    // Assert
    final state = ctx.read();
    expect(state?.hasUpstream[localPath], isFalse);
    expect(state?.unpublishedCount[localPath], 2,
        reason: 'giữ 0 của branch trước = badge Publish không bao giờ hiện');
  });

  test(
      'không stale theo chiều ngược: từ branch chưa publish quay về branch có '
      'upstream → unpublishedCount về 0', () async {
    // Arrange — lần 1 trên branch chưa publish.
    await _git(['checkout', '-q', '-b', 'feature/back'], localPath);
    await commits(localPath, 3, 'back');
    final ctx = await newNotifier();
    await ctx.notifier.loadBranchStatus(localPath);
    expect(ctx.read()?.unpublishedCount[localPath], 3);

    // Act
    await _git(['checkout', '-q', 'main'], localPath);
    await ctx.notifier.loadBranchStatus(localPath);

    // Assert
    final state = ctx.read();
    expect(state?.hasUpstream[localPath], isTrue);
    expect(state?.unpublishedCount[localPath], 0,
        reason: 'giữ 3 của branch cũ = badge Publish dính trên repo đã publish');
  });
}
