/// Data class for a single repo inside addons/
class RepoInfo {
  final String name;
  final String path;
  String branch = '';
  int changedFiles = 0;
  int aheadCount = 0;
  int behindCount = 0;
  bool hasUpstream = true;
  bool fetchFailed = false;
  bool selected = false;
  bool loaded = false;

  /// True while the background `git fetch` + behind-count refresh is running
  /// (phase 2). The tile shows local status immediately (phase 1) and a small
  /// spinner until the fresh remote counts arrive.
  bool syncing = false;

  RepoInfo({
    required this.name,
    required this.path,
  });
}
