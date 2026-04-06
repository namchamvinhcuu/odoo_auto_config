import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../l10n/l10n_extension.dart';

// ── Repo Prune Dialog ──

class RepoPruneDialog extends StatefulWidget {
  final List<String> branches;

  const RepoPruneDialog({
    super.key,
    required this.branches,
  });

  @override
  State<RepoPruneDialog> createState() => _RepoPruneDialogState();
}

class _RepoPruneDialogState extends State<RepoPruneDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.branches.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.gitBranchStaleBranches),
          const Spacer(),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthMd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.gitBranchStaleDesc,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: AppFontSize.md,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...widget.branches.map(
              (b) => CheckboxListTile(
                value: _selected.contains(b),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(b);
                    } else {
                      _selected.remove(b);
                    }
                  });
                },
                title:
                    Text(b, style: const TextStyle(fontFamily: 'monospace')),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_selected.isNotEmpty)
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected.toList()),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child:
                Text(context.l10n.gitBranchDeleteCount(_selected.length)),
          ),
      ],
    );
  }
}
