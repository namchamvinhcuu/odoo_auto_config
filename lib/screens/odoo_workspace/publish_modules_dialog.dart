import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/storage_service.dart';

// ── Publish Modules Dialog ──

/// .gitignore template for Odoo modules
const _odooGitignore = r'''# Byte-compiled / optimized / DLL files
models/__pycache__/
*.py[cod]
*$py.class

# C extensions
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# PyInstaller
*.manifest
*.spec

# Installer logs
pip-log.txt
pip-delete-this-directory.txt

# Unit test / coverage reports
htmlcov/
.tox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
.hypothesis/
.pytest_cache/

# Translations
*.mo
*.pot

# Django stuff:
*.log
local_settings.py
db.sqlite3

# Flask stuff:
instance/
.webassets-cache

# Scrapy stuff:
.scrapy

# Sphinx documentation
docs/_build/

# PyBuilder
target/

# Jupyter Notebook
.ipynb_checkpoints

# pyenv
.python-version

# celery beat schedule file
celerybeat-schedule

# SageMath parsed files
*.sage.py

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Spyder project settings
.spyderproject
.spyproject

# Rope project settings
.ropeproject

# mkdocs documentation
/site

# mypy
.mypy_cache/

# sphinx build directories
_build/

# dotfiles
.*
!.gitignore
!.github
!.mailmap
# compiled python files
*.py[co]
__pycache__/
# setup.py egg_info
*.egg-info
# emacs backup files
*~
# hg stuff
*.orig
status
# odoo filestore
odoo/filestore
# maintenance migration scripts
odoo/addons/base/maintenance

# generated for windows installer?
install/win32/*.bat
install/win32/meta.py

# needed only when building for win32
setup/win32/static/less/
setup/win32/static/wkhtmltopdf/
setup/win32/static/postgresql*.exe

# js tooling
node_modules
jsconfig.json
tsconfig.json
package-lock.json
package.json
.husky

# various virtualenv
/bin/
/build/
/dist/
/include/
/man/
/share/
/src/
*.pyc
''';

class PublishModulesDialog extends StatefulWidget {
  final String projectPath;

  const PublishModulesDialog({
    super.key,
    required this.projectPath,
  });

  @override
  State<PublishModulesDialog> createState() => _PublishModulesDialogState();
}

class _PublishModulesDialogState extends State<PublishModulesDialog> {
  List<String> _modules = [];
  final Set<String> _selected = {};
  bool _scanning = true;
  bool _publishing = false;
  final List<TextSpan> _logSpans = [];
  String? _error;

  // Git config
  String _gitOrg = '';
  String _gitToken = '';

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      // Read git-org from script file
      final shPath = p.join(widget.projectPath, 'git-repositories.sh');
      final ps1Path = p.join(widget.projectPath, 'git-repositories.ps1');
      final scriptFile = await File(shPath).exists()
          ? File(shPath)
          : (await File(ps1Path).exists() ? File(ps1Path) : null);

      if (scriptFile != null) {
        final content = await scriptFile.readAsString();
        final orgMatch =
            RegExp(r'ORG_NAME\s*=\s*"([^"]*)"').firstMatch(content);
        _gitOrg = orgMatch?.group(1) ?? '';
      }

      // Read token from git accounts
      final settings = await StorageService.loadSettings();
      if (scriptFile != null) {
        final content = await scriptFile.readAsString();
        final tokenMatch =
            RegExp(r'TOKEN\s*=\s*"([^"]*)"').firstMatch(content);
        final scriptToken = tokenMatch?.group(1) ?? '';
        // Match token to account, or use script token directly
        final accounts = (settings['gitAccounts'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final matchedAccount = accounts
            .where((a) => a['token'] == scriptToken)
            .firstOrNull;
        _gitToken = matchedAccount?['token']?.toString() ??
            scriptToken;
      }
      if (_gitToken.isEmpty) {
        // Fallback: use default account token
        final accounts = (settings['gitAccounts'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final defaultName =
            (settings['defaultGitAccount'] ?? '').toString();
        final def = accounts
            .where((a) => a['name'] == defaultName)
            .firstOrNull;
        _gitToken = def?['token']?.toString() ?? '';
      }

      // Validate
      if (_gitOrg.isEmpty ||
          _gitOrg == 'YOUR_ORGANIZATION') {
        setState(() {
          _scanning = false;
          _error = context.l10n.publishModulesNoOrg;
        });
        return;
      }
      if (_gitToken.isEmpty ||
          _gitToken == 'YOUR_GITHUB_TOKEN') {
        setState(() {
          _scanning = false;
          _error = context.l10n.publishModulesNoToken;
        });
        return;
      }

      // Scan addons/ for dirs WITHOUT .git
      final addonsDir =
          Directory(p.join(widget.projectPath, 'addons'));
      final modules = <String>[];
      if (await addonsDir.exists()) {
        await for (final entity in addonsDir.list()) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue;
            final gitDir = Directory(p.join(entity.path, '.git'));
            if (!await gitDir.exists()) {
              modules.add(name);
            }
          }
        }
      }
      modules.sort();

      setState(() {
        _modules = modules;
        _scanning = false;
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _error = e.toString();
      });
    }
  }

  void _addLog(String text, {Color color = Colors.white70}) {
    setState(() {
      _logSpans.add(TextSpan(
        text: '$text\n',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: AppFontSize.md,
          color: color,
        ),
      ));
    });
    // Auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _publish() async {
    if (_selected.isEmpty) return;

    // Cache l10n strings before async gaps
    final l10n = context.l10n;

    setState(() {
      _publishing = true;
      _logSpans.clear();
    });
    context.setDialogRunning(true);

    for (final name in _selected.toList()) {
      final modulePath = p.join(widget.projectPath, 'addons', name);

      _addLog(l10n.publishModulesCreatingRepo(name),
          color: Colors.cyan);

      // 1. Create .gitignore if missing
      final gitignoreFile = File(p.join(modulePath, '.gitignore'));
      if (!await gitignoreFile.exists()) {
        await gitignoreFile.writeAsString(_odooGitignore);
        _addLog('  [+] .gitignore', color: Colors.green);
      }

      // 2. Create README.md if missing
      final readmeFile = File(p.join(modulePath, 'README.md'));
      if (!await readmeFile.exists()) {
        await readmeFile.writeAsString('# $name\n');
        _addLog('  [+] README.md', color: Colors.green);
      }

      // 3. Create GitHub repo via API
      try {
        final result = await Process.run(
          'curl',
          [
            '-s',
            '-w', r'\n%{http_code}',
            '-X', 'POST',
            '-H', 'Authorization: token $_gitToken',
            '-H', 'Accept: application/vnd.github.v3+json',
            '-d', jsonEncode({
              'name': name,
              'private': true,
              'auto_init': false,
            }),
            'https://api.github.com/orgs/$_gitOrg/repos',
          ],
          runInShell: true,
        );

        final output = (result.stdout as String).trimRight();
        final lines = output.split('\n');
        final httpCode = lines.last.trim();
        final body = lines.sublist(0, lines.length - 1).join('\n');

        if (httpCode != '201') {
          // Check if repo already exists (422)
          if (httpCode == '422' && body.contains('already exists')) {
            _addLog('  [!] Repo already exists on GitHub, continuing...',
                color: Colors.orange);
          } else {
            final parsed = jsonDecode(body);
            final msg = parsed['message'] ?? 'HTTP $httpCode';
            _addLog(
              l10n.publishModulesFailed(name, msg.toString()),
              color: Colors.red,
            );
            continue;
          }
        } else {
          _addLog('  [+] GitHub repo created', color: Colors.green);
        }

        // 4. git init + add + commit + remote + push
        final commands = [
          ['git', 'init'],
          ['git', 'add', '-A'],
          ['git', 'commit', '-m', 'Initial commit'],
          [
            'git',
            'remote',
            'add',
            'origin',
            'https://$_gitToken@github.com/$_gitOrg/$name.git',
          ],
          ['git', 'branch', '-M', 'main'],
          ['git', 'push', '-u', 'origin', 'main'],
        ];

        var success = true;
        for (final cmd in commands) {
          final r = await Process.run(
            cmd.first,
            cmd.sublist(1),
            workingDirectory: modulePath,
            runInShell: true,
          );
          if (r.exitCode != 0) {
            final stderr = (r.stderr as String).trimRight();
            // remote add fails if already exists — skip
            if (cmd[1] == 'remote' && stderr.contains('already exists')) {
              _addLog('  [!] Remote origin already exists, updating...',
                  color: Colors.orange);
              await Process.run(
                'git',
                [
                  'remote',
                  'set-url',
                  'origin',
                  'https://$_gitToken@github.com/$_gitOrg/$name.git',
                ],
                workingDirectory: modulePath,
                runInShell: true,
              );
              continue;
            }
            _addLog('  [\u2717] ${cmd.join(' ')}', color: Colors.red);
            if (stderr.isNotEmpty) {
              _addLog('      $stderr', color: Colors.red);
            }
            success = false;
            break;
          } else {
            _addLog('  [\u2713] ${cmd.join(' ')}', color: Colors.green);
          }
        }

        if (success) {
          _addLog(
            l10n.publishModulesSuccess(name),
            color: Colors.greenAccent,
          );
        }
      } catch (e) {
        _addLog(
          l10n.publishModulesFailed(name, e.toString()),
          color: Colors.red,
        );
      }
    }

    _addLog('\nDone.', color: Colors.white);
    if (mounted) {
      setState(() => _publishing = false);
      context.setDialogRunning(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.cloud_upload),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(context.l10n.publishModules),
          ),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        height: AppDialog.heightXl,
        child: _scanning
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.l10n.publishModulesScanning,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: AppIconSize.xxl),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  )
                : _modules.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.publishModulesNoModules,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Info bar
                          Text(
                            '${context.l10n.publishModulesSelect}'
                            '  \u2022  org: $_gitOrg'
                            '  \u2022  ${_modules.length} modules',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: AppFontSize.md,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // Module list
                          if (!_publishing)
                            Expanded(
                              child: ListView.builder(
                                itemCount: _modules.length,
                                itemBuilder: (ctx, i) {
                                  final name = _modules[i];
                                  final checked =
                                      _selected.contains(name);
                                  return ListTile(
                                    dense: true,
                                    leading: Checkbox(
                                      value: checked,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selected.add(name);
                                          } else {
                                            _selected.remove(name);
                                          }
                                        });
                                      },
                                    ),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        if (checked) {
                                          _selected.remove(name);
                                        } else {
                                          _selected.add(name);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          // Log output (shown during/after publish)
                          if (_logSpans.isNotEmpty)
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                    AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius:
                                      AppRadius.mediumBorderRadius,
                                ),
                                child: SelectionArea(
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    child: Text.rich(
                                      TextSpan(children: _logSpans),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
      actions: _error != null || _scanning || _modules.isEmpty
          ? null
          : [
              if (!_publishing)
                FilledButton.icon(
                  onPressed:
                      _selected.isEmpty ? null : _publish,
                  icon: const Icon(Icons.cloud_upload,
                      size: AppIconSize.md),
                  label: Text(
                    '${context.l10n.publishModulesPublish}'
                    ' (${_selected.length})',
                  ),
                ),
              if (_publishing)
                const SizedBox(
                  width: AppIconSize.lg,
                  height: AppIconSize.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
    );
  }
}
