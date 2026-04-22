import 'dart:io';
import 'package:path/path.dart' as p;

/// One file in a discard operation. Status is the 2-char code from
/// `git status --porcelain` (e.g. "M", "??", "A", "D", "MM").
class DiscardItem {
  final String status;
  final String file;
  const DiscardItem({required this.status, required this.file});

  bool get isUntracked => status == '??';
}

class DiscardOutcome {
  final List<String> restored;
  final List<String> deleted;
  final List<String> errors;
  const DiscardOutcome({
    required this.restored,
    required this.deleted,
    required this.errors,
  });

  bool get hasError => errors.isNotEmpty;
}

/// Discard uncommitted changes for a set of files in a single repo.
///
/// Behavior:
///   - Untracked (`??`): permanently delete the file from disk.
///   - Tracked (M/A/D/R/MM/...): `git checkout HEAD -- <file>` to revert
///     both staged and unstaged changes.
///
/// Destructive and NOT recoverable. Callers must confirm with the user first.
class GitDiscardService {
  static Future<DiscardOutcome> discard({
    required String repoPath,
    required List<DiscardItem> items,
  }) async {
    final restored = <String>[];
    final deleted = <String>[];
    final errors = <String>[];

    final untracked = items.where((i) => i.isUntracked).toList();
    final tracked = items.where((i) => !i.isUntracked).toList();

    // Tracked: one `git checkout HEAD -- <files...>` call handles all at once.
    if (tracked.isNotEmpty) {
      final args = <String>['checkout', 'HEAD', '--'];
      args.addAll(tracked.map((t) => t.file));
      final result = await Process.run(
        'git',
        args,
        workingDirectory: repoPath,
        runInShell: true,
      );
      if (result.exitCode == 0) {
        restored.addAll(tracked.map((t) => t.file));
      } else {
        final err = (result.stderr as String).trim();
        errors.add(err.isEmpty
            ? 'git checkout failed (exit ${result.exitCode})'
            : err);
      }
    }

    // Untracked: delete each file from disk. Best-effort per file so one
    // failure doesn't block the rest.
    for (final item in untracked) {
      try {
        final full = p.join(repoPath, item.file);
        final entity = FileSystemEntity.typeSync(full);
        if (entity == FileSystemEntityType.directory) {
          await Directory(full).delete(recursive: true);
        } else if (entity != FileSystemEntityType.notFound) {
          await File(full).delete();
        }
        deleted.add(item.file);
      } catch (e) {
        errors.add('Delete failed for ${item.file}: $e');
      }
    }

    return DiscardOutcome(
      restored: restored,
      deleted: deleted,
      errors: errors,
    );
  }
}
