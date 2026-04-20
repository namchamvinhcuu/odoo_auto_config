import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Spacing constants used throughout the app
class AppSpacing {
  static const double xxs = 2;
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
  static const double statusIcon = 18;
  static const double lg = 24;
  static const double xl = 28;
  static const double xxl = 40;
  static const double xxxl = 48;
  static const double feature = 64;
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

  // Container heights for lists and log outputs
  static const double listHeightSm = 120;
  static const double listHeight = 150;
  static const double logHeightSm = 180;
  static const double logHeightMd = 200;
  static const double logHeightLg = 250;
  static const double logHeightXl = 350;

  /// Max height for dialog content area (70% of screen height).
  static double contentMaxHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.7;

  /// Show a draggable dialog that cannot be dismissed by tapping outside.
  ///
  /// ESC is allowed by default. When the dialog is running a process, call
  /// `context.setDialogRunning(true)` (and `false` when done) — this blocks
  /// ESC and automatically disables [closeButton]. All centralized in one
  /// place so dialogs do not need their own `PopScope` wrapper.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
  }) {
    final controller = _DialogProcessController();
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogProcessScope(
        notifier: controller,
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, __) => PopScope(
            canPop: !controller.running,
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (!controller.running && Navigator.canPop(ctx)) {
                    Navigator.pop(ctx);
                  }
                },
              },
              child: Focus(
                autofocus: true,
                child: _DraggableDialog(child: builder(ctx)),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  /// Red X close button for dialog title rows.
  /// Use in title Row: `[...other widgets, const Spacer(), AppDialog.closeButton(context)]`
  ///
  /// Auto-disabled while the enclosing dialog is marked running via
  /// `context.setDialogRunning(true)`. Pass [enabled] to override manually.
  static Widget closeButton(
    BuildContext context, {
    VoidCallback? onClose,
    bool? enabled,
  }) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DialogProcessScope>();
    if (scope == null || enabled != null) {
      return _renderCloseButton(
        context,
        enabled: enabled ?? true,
        onClose: onClose,
      );
    }
    return AnimatedBuilder(
      animation: scope.notifier!,
      builder: (ctx, _) => _renderCloseButton(
        ctx,
        enabled: !scope.notifier!.running,
        onClose: onClose,
      ),
    );
  }

  static Widget _renderCloseButton(
    BuildContext context, {
    required bool enabled,
    VoidCallback? onClose,
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

/// Signal whether the enclosing dialog is running a process.
///
/// Blocks ESC and disables [AppDialog.closeButton] while true. Safe to call
/// outside an [AppDialog.show] context — it becomes a no-op.
///
/// Uses `getInheritedWidgetOfExactType` (not `dependOn...`) so callers do not
/// register as dependents. This means it is safe to call from `initState`,
/// and the caller does not rebuild when the scope's value changes — which is
/// the right behavior for a fire-and-forget setter.
extension DialogProcessContextX on BuildContext {
  void setDialogRunning(bool running) {
    final scope = getInheritedWidgetOfExactType<_DialogProcessScope>();
    scope?.notifier?.setRunning(running);
  }

  /// Whether the enclosing dialog is currently running a process.
  /// Returns `false` if called outside [AppDialog.show].
  bool get isDialogRunning =>
      getInheritedWidgetOfExactType<_DialogProcessScope>()
          ?.notifier
          ?.running ??
      false;

  /// Run [task] with the dialog marked as running; automatically release
  /// on completion (success or failure). Avoids forgetting `setDialogRunning(false)`.
  Future<T> runDialogProcess<T>(Future<T> Function() task) async {
    setDialogRunning(true);
    try {
      return await task();
    } finally {
      setDialogRunning(false);
    }
  }
}

class _DialogProcessController extends ChangeNotifier {
  bool _running = false;
  bool get running => _running;
  void setRunning(bool v) {
    if (_running == v) return;
    _running = v;
    // Defer notification if called during build (e.g. from initState) so we
    // don't `markNeedsBuild` on ancestors mid-frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }
}

class _DialogProcessScope
    extends InheritedNotifier<_DialogProcessController> {
  const _DialogProcessScope({
    required _DialogProcessController super.notifier,
    required super.child,
  });
}

/// Icons for git/action buttons — consistent across all views
class GitActionIcons {
  static const IconData pull = Icons.download;
  static const IconData commit = Icons.commit;
  static const IconData push = Icons.commit;
  static const IconData pr = Icons.merge;
  static const IconData prBar = Icons.merge_type;
  static const IconData publish = Icons.cloud_upload;
  static const IconData delete = Icons.delete_outline;
  static const IconData branch = Icons.account_tree;
  static const IconData refresh = Icons.refresh;
}

/// Colors for git/action buttons — consistent across all views
class GitActionColors {
  static const Color pull = Colors.blue;
  static const Color commit = Colors.orange;
  static const Color push = Colors.orange;
  static const Color pr = Colors.purpleAccent;
  static const Color publish = Colors.green;
  static const Color delete = Colors.red;
  static const Color refresh = Colors.teal;
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
  final ValueNotifier<Offset> _offset = ValueNotifier(Offset.zero);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerMove: (event) {
        if (event.buttons != 0 || event.down) {
          _offset.value += event.delta;
        }
      },
      child: ValueListenableBuilder<Offset>(
        valueListenable: _offset,
        builder: (_, offset, child) => Transform.translate(
          offset: offset,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
