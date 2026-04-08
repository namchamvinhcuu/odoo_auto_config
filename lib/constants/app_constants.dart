import 'package:flutter/material.dart';

/// Spacing constants used throughout the app
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Common EdgeInsets
  static const screenPadding = EdgeInsets.all(xxl);
  static const cardPadding = EdgeInsets.all(lg);
  static const dialogPadding = EdgeInsets.all(xxl);
  static const chipPadding = EdgeInsets.symmetric(horizontal: md, vertical: sm);
}

/// Font size constants
class AppFontSize {
  static const double xs = 11;
  static const double sm = 12;
  static const double md = 13;
  static const double lg = 16;
  static const double xl = 17;
  static const double xxl = 18;
  static const double title = 28;
}

/// Icon size constants
class AppIconSize {
  static const double sm = 14;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 28;
  static const double xxl = 40;
}

/// Border radius constants
class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 24;

  static final smallBorderRadius = BorderRadius.circular(sm);
  static final mediumBorderRadius = BorderRadius.circular(md);
  static final largeBorderRadius = BorderRadius.circular(lg);
  static final circularBorderRadius = BorderRadius.circular(xl);
}

/// Dialog dimension constants
class AppDialog {
  static const double widthSm = 500;
  static const double widthMd = 700;
  static const double widthLg = 800;
  static const double widthXl = 900;

  static const double heightSm = 400;
  static const double heightMd = 450;
  static const double heightLg = 700;
  static const double heightXl = 750;

  /// Show a draggable dialog that cannot be dismissed by tapping outside or pressing ESC.
  /// Use this instead of [showDialog] for all app dialogs.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          PopScope(canPop: false, child: _DraggableDialog(child: builder(ctx))),
    );
  }

  /// Red X close button for dialog title rows.
  /// Use in title Row: `[...other widgets, const Spacer(), AppDialog.closeButton(context)]`
  /// Set [enabled] to false to disable close (e.g. while process is running).
  static Widget closeButton(
    BuildContext context, {
    VoidCallback? onClose,
    bool enabled = true,
  }) {
    return IconButton(
      onPressed: enabled ? (onClose ?? () => Navigator.pop(context)) : null,
      icon: const Icon(Icons.close, color: Colors.white, size: AppIconSize.md),
      style: IconButton.styleFrom(
        backgroundColor: enabled ? Colors.red : Colors.grey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        minimumSize: const Size(AppIconSize.xl, AppIconSize.xl),
        padding: EdgeInsets.zero,
      ),
      tooltip: 'Close',
    );
  }
}

/// Colors used in log output
class AppLogColors {
  static const Color success = Colors.greenAccent;
  static const Color error = Colors.redAccent;
  static const Color warning = Colors.orangeAccent;
  static const Color terminalBg = Color(0xFF1E1E1E);
}

/// NavigationRail constants
class AppNav {
  static const double minExtendedWidth = 220;
}

/// Wrapper that makes any dialog draggable by its title bar area.
class _DraggableDialog extends StatefulWidget {
  final Widget child;
  const _DraggableDialog({required this.child});

  @override
  State<_DraggableDialog> createState() => _DraggableDialogState();
}

class _DraggableDialogState extends State<_DraggableDialog> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: _offset,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() => _offset += details.delta);
        },
        child: widget.child,
      ),
    );
  }
}

// test
