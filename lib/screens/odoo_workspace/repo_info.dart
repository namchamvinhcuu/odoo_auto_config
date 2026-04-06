/// Data class for a single repo inside addons/
class RepoInfo {
  final String name;
  final String path;
  String branch = '';
  int changedFiles = 0;
  int aheadCount = 0;
  int behindCount = 0;
  bool hasUpstream = true;
  bool selected = false;
  bool loaded = false;

  RepoInfo({
    required this.name,
    required this.path,
  });
}
