import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';

class NginxSetupDialog extends StatefulWidget {
  final String initialSubdomain;
  final String domainSuffix;
  final int? initialPort;
  final bool showPort;

  const NginxSetupDialog({
    super.key,
    required this.initialSubdomain,
    required this.domainSuffix,
    this.initialPort,
    this.showPort = false,
  });

  @override
  State<NginxSetupDialog> createState() => _NginxSetupDialogState();
}

class _NginxSetupDialogState extends State<NginxSetupDialog> {
  late final TextEditingController _subdomainController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    _subdomainController =
        TextEditingController(text: widget.initialSubdomain);
    _portController = TextEditingController(
        text: widget.initialPort != null ? '${widget.initialPort}' : '');
  }

  @override
  void dispose() {
    _subdomainController.dispose();
    _portController.dispose();
    super.dispose();
  }

  String get _previewDomain =>
      '${_subdomainController.text}${widget.domainSuffix}';

  bool get _isValid {
    if (_subdomainController.text.trim().isEmpty) return false;
    if (widget.showPort) {
      final port = int.tryParse(_portController.text.trim());
      if (port == null || port <= 0) return false;
    }
    return true;
  }

  void _submit() {
    if (!_isValid) return;
    final subdomain = _subdomainController.text.trim();
    final port = widget.showPort
        ? int.tryParse(_portController.text.trim())
        : null;
    Navigator.pop(context, (subdomain: subdomain, port: port));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.nginxSetup),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _subdomainController,
              decoration: InputDecoration(
                labelText: context.l10n.nginxSubdomain,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixText: widget.domainSuffix,
              ),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            if (widget.showPort) ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: context.l10n.wsPort,
                  hintText: context.l10n.wsPortHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l10n.nginxPreviewDomain(_previewDomain),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppFontSize.sm,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel)),
        FilledButton(
          onPressed: _isValid ? _submit : null,
          child: Text(context.l10n.nginxSetup),
        ),
      ],
    );
  }
}
