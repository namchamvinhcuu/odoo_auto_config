import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/services/command_runner.dart';
import 'package:odoo_auto_config/services/platform_service.dart';
import 'package:odoo_auto_config/widgets/log_output.dart';

class VscodeInstallDialog extends StatefulWidget {
  const VscodeInstallDialog({super.key});

  @override
  State<VscodeInstallDialog> createState() => _VscodeInstallDialogState();
}

class _VscodeInstallDialogState extends State<VscodeInstallDialog> {
  bool _installing = false;
  bool _installed = false;
  final List<String> _logLines = [];

  Future<void> _install() async {
    final cmd = PlatformService.vscodeInstallCommand();
    setState(() {
      _installing = true;
      _logLines.clear();
      _logLines.add('[+] Running: ${cmd.description}');
      _logLines.add('');
    });

    try {
      final process = await Process.start(
        cmd.executable,
        cmd.args,
        runInShell: true,
      );

      String lastLine = '';
      final stdoutDone = process.stdout.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) {
            continue;
          }
          lastLine = cleaned;
          if (mounted) {
            setState(() => _logLines.add(cleaned));
          }
        }
      }).asFuture();

      final stderrDone = process.stderr.transform(utf8.decoder).listen((data) {
        for (final line in data.split('\n')) {
          final cleaned = CommandRunner.cleanLine(line);
          if (cleaned == null) continue;
          if (cleaned == CommandRunner.spinnerPlaceholder &&
              lastLine == cleaned) {
            continue;
          }
          lastLine = cleaned;
          if (mounted) {
            setState(() => _logLines.add('[WARN] $cleaned'));
          }
        }
      }).asFuture();

      await Future.wait([stdoutDone, stderrDone]);
      final exitCode = await process.exitCode;

      if (mounted) {
        setState(() {
          _installing = false;
          if (exitCode == 0) {
            _installed = true;
            _logLines.add('');
            _logLines.add('[+] VSCode installed successfully!');
            if (PlatformService.isWindows) {
              _logLines.add(
                  '[+] Please restart the app for VSCode to be detected.');
            }
          } else {
            _logLines.add('');
            _logLines.add(
                '[ERROR] Installation failed with exit code $exitCode');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _logLines.add('[ERROR] $e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.installVscode),
      content: SizedBox(
        width: AppDialog.widthSm,
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: AppDialog.contentMaxHeight(context),
            ),
            child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(
              context.l10n.installVscodeSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
            if (_logLines.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              LogOutput(lines: _logLines, height: AppDialog.logHeightMd),
            ],
          ],
          ),
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        if (!_installed)
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: AppIconSize.md,
                    height: AppIconSize.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(
                _installing ? context.l10n.installing : context.l10n.install),
          ),
      ],
    );
  }
}
