import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../l10n/l10n_extension.dart';

class LogOutput extends StatefulWidget {
  final List<String> lines;
  final double height;

  const LogOutput({
    super.key,
    required this.lines,
    this.height = 250,
  });

  @override
  State<LogOutput> createState() => _LogOutputState();
}

class _LogOutputState extends State<LogOutput> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LogOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length > oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppLogColors.terminalBg,
        borderRadius: AppRadius.mediumBorderRadius,
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: widget.lines.isEmpty
          ? Center(
              child: Text(
                context.l10n.noOutputYet,
                style: const TextStyle(color: Colors.grey, fontFamily: 'monospace'),
              ),
            )
          : SelectionArea(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(AppSpacing.md),
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final line = widget.lines[index];
                  return Text(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: AppFontSize.md,
                      color: _getLineColor(line),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Color _getLineColor(String line) {
    if (line.startsWith('[+]')) return AppLogColors.success;
    if (line.startsWith('[-]') || line.startsWith('[ERROR]')) {
      return AppLogColors.error;
    }
    if (line.startsWith('[=]') || line.startsWith('[WARN]')) {
      return AppLogColors.warning;
    }
    return Colors.grey.shade300;
  }
}
