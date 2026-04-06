import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';

// ── Branch Picker Dialog ──

class BranchPickerDialog extends StatefulWidget {
  final List<String> branches;
  final TextEditingController controller;
  final Color Function(String) branchColor;

  const BranchPickerDialog({
    super.key,
    required this.branches,
    required this.controller,
    required this.branchColor,
  });

  @override
  State<BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends State<BranchPickerDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? widget.branches
        : widget.branches
            .where((b) => b.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.workspaceViewSwitchBranch),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthSm,
        height: AppDialog.heightMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search / create
            TextField(
              controller: widget.controller,
              decoration: InputDecoration(
                hintText: context.l10n.workspaceViewNewBranch,
                prefixIcon:
                    const Icon(Icons.search, size: AppIconSize.md),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Branch list
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final branch = filtered[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.account_tree,
                      size: AppIconSize.md,
                      color: widget.branchColor(branch),
                    ),
                    title: Text(
                      branch,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: widget.branchColor(branch),
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, branch),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.controller.text.trim().isNotEmpty)
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, widget.controller.text.trim()),
            child: Text(context.l10n.workspaceViewCreateBranch),
          ),
      ],
    );
  }
}
