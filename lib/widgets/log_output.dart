import 'package:flutter/material.dart';
import 'package:odoo_auto_config/constants/app_constants.dart';
import 'package:odoo_auto_config/l10n/l10n_extension.dart';
import 'package:odoo_auto_config/widgets/ansi_parser.dart';

/// Reusable log output container with terminal styling, auto-scroll, and text selection.
///
/// Supports two rendering modes:
/// - **Plain** (default): colored by line prefix (`[+]`, `[-]`, `[WARN]`)
/// - **ANSI** (`ansiColors: true`): parses ANSI escape codes via [AnsiParser]
///
/// Use [height] for fixed-height containers (install dialogs, etc.),
/// or [maxHeight] for flexible containers inside `Flexible` widgets (commit dialogs).
///
/// Accepts an optional [scrollController] for external scroll control (auto-scroll on new lines).
/// If not provided, creates its own internal controller.
class LogOutput extends StatefulWidget {
  final List<String> lines;

  /// Fixed height — use for dialogs wrapped in SingleChildScrollView.
  final double? height;

  /// Max height — use inside Flexible for per-section scroll.
  final double? maxHeight;

  /// Parse ANSI escape codes for colored output.
  final bool ansiColors;

  /// Optional external ScrollController (for auto-scroll from parent).
  final ScrollController? scrollController;

  const LogOutput({
    super.key,
    required this.lines,
    this.height,
    this.maxHeight,
    this.ansiColors = false,
    this.scrollController,
  });

  @override
  State<LogOutput> createState() => _LogOutputState();
}

class _LogOutputState extends State<LogOutput> {
  ScrollController? _ownController;

  ScrollController get _scrollController =>
      widget.scrollController ?? (_ownController ??= ScrollController());

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
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      constraints: widget.maxHeight != null
          ? BoxConstraints(maxHeight: widget.maxHeight!)
          : null,
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
                style: const TextStyle(
                    color: Colors.grey, fontFamily: 'monospace'),
              ),
            )
          : SelectionArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in widget.lines)
                        widget.ansiColors
                            ? Text.rich(
                                TextSpan(
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: AppFontSize.md,
                                  ),
                                  children: AnsiParser.parse(line),
                                ),
                              )
                            : Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: AppFontSize.md,
                                  color: _getLineColor(line),
                                ),
                              ),
                    ],
                  ),
                ),
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
