import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/platform_service.dart';

class PipInstallDialog extends StatefulWidget {
  final String venvPath;
  final String venvName;

  const PipInstallDialog(
      {super.key, required this.venvPath, required this.venvName});

  @override
  State<PipInstallDialog> createState() => _PipInstallDialogState();
}

class _PipInstallDialogState extends State<PipInstallDialog> {
  final _controller = TextEditingController();
  final _logs = <String>[];
  bool _installing = false;

  Future<void> _install() async {
    var input = _controller.text.trim();
    if (input.isEmpty) return;

    // Strip "pip install" prefix if user typed it
    input = input.replaceFirst(
        RegExp(r'^pip\s+install\s+', caseSensitive: false), '');
    if (input.isEmpty) return;

    setState(() {
      _installing = true;
      _logs.add('[+] pip install $input');
      _logs.add('    Venv: ${widget.venvPath}');
      _logs.add('');
    });
    context.setDialogRunning(true);

    final pip = PlatformService.venvPip(widget.venvPath);
    final args = input.split(RegExp(r'\s+'));
    final result =
        await Process.run(pip, ['install', ...args], runInShell: true);

    if (!mounted) return;

    setState(() {
      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();
      if (result.exitCode == 0) {
        if (stdout.isNotEmpty) _logs.addAll(stdout.split('\n'));
        _logs.add('');
        _logs.add('[+] Packages installed successfully!');
      } else {
        _logs.add('[ERROR] Installation failed');
        if (stderr.isNotEmpty) _logs.addAll(stderr.split('\n'));
      }
      _installing = false;
      _controller.clear();
    });
    context.setDialogRunning(false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.add_box),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(
                  context.l10n.installPackagesTitle(widget.venvName))),
          AppDialog.closeButton(context),
        ],
      ),
      content: SizedBox(
        width: AppDialog.widthMd,
        height: AppDialog.heightSm,
        child: Column(
          children: [
            Text(widget.venvPath,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppFontSize.xs,
                    color: Colors.grey.shade500)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: context.l10n.packagesField,
                      hintText: context.l10n.packagesFieldHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    enabled: !_installing,
                    autofocus: true,
                    onSubmitted: (_) => _install(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _installing ? null : _install,
                  child: _installing
                      ? const SizedBox(
                          width: AppIconSize.md,
                          height: AppIconSize.md,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(context.l10n.install),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppLogColors.terminalBg,
                  borderRadius: AppRadius.mediumBorderRadius,
                  border: Border.all(color: Colors.grey.shade700),
                ),
                child: _logs.isEmpty
                    ? Center(
                        child: Text(context.l10n.outputPlaceholder,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace')),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(AppSpacing.md),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final line = _logs[index];
                          Color color = Colors.grey.shade300;
                          if (line.startsWith('[+]')) {
                            color = AppLogColors.success;
                          } else if (line.startsWith('[ERROR]')) {
                            color = AppLogColors.error;
                          }
                          return Text(line,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.sm,
                                  color: color));
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
