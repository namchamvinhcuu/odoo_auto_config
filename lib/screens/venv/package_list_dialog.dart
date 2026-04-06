import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';
import '../../services/platform_service.dart';

class PkgInfo {
  final String name;
  final String version;
  const PkgInfo({required this.name, required this.version});
}

class PackageListDialog extends StatefulWidget {
  final String venvPath;

  const PackageListDialog({super.key, required this.venvPath});

  @override
  State<PackageListDialog> createState() => _PackageListDialogState();
}

class _PackageListDialogState extends State<PackageListDialog> {
  final _searchController = TextEditingController();
  List<PkgInfo> _all = [];
  List<PkgInfo> _filtered = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final pip = PlatformService.venvPip(widget.venvPath);
    try {
      final result = await Process.run(pip, ['list', '--format=json']);
      if (result.exitCode == 0) {
        final list = (jsonDecode(result.stdout.toString()) as List<dynamic>)
            .map((e) => PkgInfo(
                  name: e['name']?.toString() ?? '',
                  version: e['version']?.toString() ?? '',
                ))
            .toList();
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() {
          _all = list;
          _applyFilter();
          _loading = false;
        });
      } else {
        setState(() {
          _error = result.stderr.toString();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchController.text.toLowerCase();
    _filtered = q.isEmpty
        ? _all
        : _all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.list_alt),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(context.l10n.installedPackages)),
          if (!_loading)
            Text(context.l10n.packagesCount(_all.length),
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: AppSpacing.sm),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: AppDialog.heightMd,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.searchPackages,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _applyFilter());
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() => _applyFilter()),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(
                child: Center(
                    child: Text(context.l10n.errorLabel(_error!),
                        style: const TextStyle(color: Colors.red))),
              )
            else ...[
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadius.md)),
                ),
                child: Row(
                  children: [
                    Expanded(
                        flex: 3,
                        child: Text(context.l10n.packageHeader,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        child: Text(context.l10n.versionHeader,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              // Table body
              Expanded(
                child: _filtered.isEmpty
                    ? Center(child: Text(context.l10n.noPackagesFound))
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final pkg = _filtered[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 6),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                    color:
                                        Colors.grey.withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(pkg.name,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: AppFontSize.md)),
                                ),
                                Expanded(
                                  child: Text(pkg.version,
                                      style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: AppFontSize.md,
                                          color: Colors.grey.shade500)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
