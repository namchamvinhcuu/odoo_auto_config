import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';
import '../services/nginx_service.dart';

class NginxSetupDialog extends StatefulWidget {
  final String initialSubdomain;
  final String domainSuffix;
  final int? initialPort;
  final bool showPort;
  /// Existing subdomain conf names (without .conf), for conflict check
  final Set<String> existingSubdomains;
  /// Ports already proxied: port -> project name
  final Map<int, String> usedPorts;

  const NginxSetupDialog({
    super.key,
    required this.initialSubdomain,
    required this.domainSuffix,
    this.initialPort,
    this.showPort = false,
    this.existingSubdomains = const {},
    this.usedPorts = const {},
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

  String? get _subdomainError {
    final sub = _subdomainController.text.trim();
    if (sub.isEmpty) return null;
    final confName = NginxService.getConfFileName(sub);
    final baseName = confName.replaceAll('.conf', '');
    if (widget.existingSubdomains.contains(baseName)) {
      return context.l10n.nginxDomainConflict;
    }
    return null;
  }

  String? get _portError {
    if (!widget.showPort) return null;
    final portText = _portController.text.trim();
    if (portText.isEmpty) return null;
    final port = int.tryParse(portText);
    if (port == null || port <= 0) return null;
    final owner = widget.usedPorts[port];
    if (owner != null) {
      return context.l10n.nginxPortConflict(port, owner);
    }
    return null;
  }

  bool get _isValid {
    if (_subdomainController.text.trim().isEmpty) return false;
    if (_subdomainError != null) return false;
    if (widget.showPort) {
      final port = int.tryParse(_portController.text.trim());
      if (port == null || port <= 0) return false;
      if (_portError != null) return false;
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
                errorText: _subdomainError,
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
                  errorText: _portError,
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
                color: _subdomainError == null
                    ? Theme.of(context).colorScheme.primary
                    : Colors.red,
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
