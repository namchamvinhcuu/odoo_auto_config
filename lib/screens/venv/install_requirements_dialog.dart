import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/services/venv_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class InstallRequirementsDialog extends StatefulWidget {
  final String venvPath;
  final String requirementsFile;
  final VenvService venvService;

  const InstallRequirementsDialog({
    super.key,
    required this.venvPath,
    required this.requirementsFile,
    required this.venvService,
  });

  @override
  State<InstallRequirementsDialog> createState() =>
      _InstallRequirementsDialogState();
}

class _InstallRequirementsDialogState
    extends State<InstallRequirementsDialog> {
  final _logs = <String>[];
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _logs.add('[+] Installing packages from: ${widget.requirementsFile}');
      _logs.add('    Venv: ${widget.venvPath}');
      _logs.add('    pip: ${PlatformService.venvPip(widget.venvPath)}');
      _logs.add('');
    });

    final result = await widget.venvService.installRequirements(
      widget.venvPath,
      widget.requirementsFile,
    );

    if (!mounted) return;

    setState(() {
      if (result.isSuccess) {
        if (result.stdout.isNotEmpty) {
          _logs.addAll(result.stdout.split('\n'));
        }
        _logs.add('');
        _logs.add('[+] Requirements installed successfully!');
      } else {
        _logs.add('[ERROR] Installation failed');
        if (result.stderr.isNotEmpty) {
          _logs.addAll(result.stderr.split('\n'));
        }
      }
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Text(context.l10n.installRequirements),
          const Spacer(),
          if (_running)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          AppDialog.closeButton(context, enabled: !_running),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: LogOutput(lines: _logs),
      ),
    );
  }
}
