import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/storage_service.dart';
import 'selective_pull_log_dialog.dart';

class SelectivePullDialog extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const SelectivePullDialog({
    super.key,
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<SelectivePullDialog> createState() => _SelectivePullDialogState();
}

class _SelectivePullDialogState extends State<SelectivePullDialog> {
  List<String> _allRepos = [];
  List<String> _selectedRepos = [];
  bool _loading = true;

  // Persist key for this project
  String get _storageKey => 'selectivePull_${widget.projectPath}';

  @override
  void initState() {
    super.initState();
    _scanRepos();
  }

  Future<void> _scanRepos() async {
    setState(() => _loading = true);
    try {
      final addonsDir = Directory(p.join(widget.projectPath, 'addons'));
      final repos = <String>[];
      await for (final entity in addonsDir.list()) {
        if (entity is Directory) {
          final gitDir = Directory(p.join(entity.path, '.git'));
          if (await gitDir.exists()) {
            repos.add(p.basename(entity.path));
          }
        }
      }
      repos.sort();

      // Load persisted selection
      final settings = await StorageService.loadSettings();
      final saved = (settings[_storageKey] as List?)
              ?.map((e) => e.toString())
              .where((r) => repos.contains(r))
              .toList() ??
          [];

      if (mounted) {
        setState(() {
          _allRepos = repos;
          _selectedRepos = saved;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSelection() async {
    await StorageService.updateSettings((settings) {
      settings[_storageKey] = _selectedRepos;
    });
  }

  void _addRepo(String repo) {
    if (_selectedRepos.contains(repo)) return;
    setState(() => _selectedRepos.add(repo));
    _saveSelection();
  }

  void _removeRepo(String repo) {
    setState(() => _selectedRepos.remove(repo));
    _saveSelection();
  }

  void _clearAll() {
    setState(() => _selectedRepos.clear());
    _saveSelection();
  }

  void _pull() {
    if (_selectedRepos.isEmpty) return;
    AppDialog.show(
      context: context,
      builder: (ctx) => SelectivePullLogDialog(
        projectPath: widget.projectPath,
        repos: List.from(_selectedRepos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitSelectivePullTitle(widget.projectName)),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_allRepos.isEmpty)
              Center(child: Text(context.l10n.gitNoReposFound))
            else ...[
              // Search bar
              Row(
                children: [
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        final q = textEditingValue.text.toLowerCase();
                        if (q.isEmpty) return _allRepos.where((r) => !_selectedRepos.contains(r));
                        return _allRepos.where((r) =>
                            r.toLowerCase().contains(q) &&
                            !_selectedRepos.contains(r));
                      },
                      onSelected: _addRepo,
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: context.l10n.gitSearchRepo,
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        );
                      },
                      optionsViewBuilder: (ctx, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: AppRadius.mediumBorderRadius,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (ctx, i) {
                                  final repo = options.elementAt(i);
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.source, size: AppIconSize.md),
                                    title: Text(repo, style: const TextStyle(fontFamily: 'monospace')),
                                    onTap: () => onSelected(repo),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Selected repos header
              Row(
                children: [
                  Text(
                    context.l10n.gitSelectedRepos(_selectedRepos.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_selectedRepos.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: const Icon(Icons.clear_all, size: AppIconSize.md),
                      label: Text(context.l10n.gitClearList),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // Selected repos list
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade700),
                  borderRadius: AppRadius.mediumBorderRadius,
                ),
                child: _selectedRepos.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.gitSearchRepo,
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _selectedRepos.length,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        itemBuilder: (ctx, i) {
                          final repo = _selectedRepos[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.source, size: AppIconSize.md, color: Colors.green),
                            title: Text(repo,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: AppFontSize.md)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: AppIconSize.md),
                              onPressed: () => _removeRepo(repo),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_selectedRepos.isNotEmpty)
          FilledButton.icon(
            onPressed: _pull,
            icon: const Icon(Icons.sync, size: AppIconSize.md),
            label: Text(context.l10n.gitPullSelected),
          ),
      ],
    );
  }
}
