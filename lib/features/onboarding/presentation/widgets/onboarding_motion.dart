/// Onboarding's motion (onboarding spec §10): playful only at the splash, the
/// welcome and the lock; quick and calm in between. No loops. Under reduced
/// motion every entrance is instant and every step change a 150ms crossfade.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Says [message] to a screen reader (TalkBack), for this window.
void onbAnnounce(BuildContext context, String message) {
  final view = View.maybeOf(context);
  if (view == null) return;
  SemanticsService.sendAnnouncement(
    view,
    message,
    Directionality.maybeOf(context) ?? TextDirection.ltr,
  );
}

bool onbReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A one-shot entrance: fade, rise and (optionally) scale, after [delay].
/// One controller with an [Interval] — no timers — so it can never fire after
/// the widget is gone.
class OnbReveal extends StatefulWidget {
  const OnbReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
    this.rise = 12,
    this.scaleFrom = 1,
    this.fade = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  /// dp the child rises from.
  final double rise;
  final double scaleFrom;
  final bool fade;

  @override
  State<OnbReveal> createState() => _OnbRevealState();
}

class _OnbRevealState extends State<OnbReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds /
          (widget.delay + widget.duration).inMicroseconds,
      1,
      curve: widget.curve,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (onbReduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final t = _t.value;
      final opacityT =
          widget.fade
              ? Interval(
                widget.delay.inMicroseconds /
                    (widget.delay + widget.duration).inMicroseconds,
                1,
              ).transform(_controller.value)
              : 1.0;
      return Opacity(
        opacity: opacityT.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, widget.rise * (1 - t)),
          child: Transform.scale(
            scale: widget.scaleFrom + (1 - widget.scaleFrom) * t,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Step-to-step: shared axis X — in from +30dp and fading, out to −30dp
/// (mirrored going back), 300ms emphasized; 150ms crossfade when reduced.
Widget sharedAxisTransition({
  required Widget child,
  required Animation<double> animation,
  required bool forward,
  required bool reduceMotion,
}) {
  if (reduceMotion) return FadeTransition(opacity: animation, child: child);
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final incoming = animation.status != AnimationStatus.reverse;
      final t = Curves.easeInOutCubicEmphasized.transform(animation.value);
      final direction = forward ? 1.0 : -1.0;
      final dx =
          incoming ? 30 * (1 - t) * direction : -30 * (1 - t) * direction;
      final opacity =
          incoming
              ? const Interval(.3, 1).transform(animation.value)
              : const Interval(.5, 1).transform(animation.value);
      return Opacity(
        opacity: opacity,
        child: Transform.translate(offset: Offset(dx, 0), child: child),
      );
    },
  );
}

/// The splash → destination and R → Home hand-off: fade-through.
class FadeThroughRoute<T> extends PageRouteBuilder<T> {
  FadeThroughRoute({
    required WidgetBuilder builder,
    Duration duration = const Duration(milliseconds: 240),
    super.settings,
  }) : super(
         transitionDuration: duration,
         reverseTransitionDuration: const Duration(milliseconds: 150),
         pageBuilder: (context, _, __) => builder(context),
         transitionsBuilder: (context, animation, secondary, child) {
           final reduce = onbReduceMotion(context);
           final inT =
               reduce
                   ? animation
                   : CurvedAnimation(
                     parent: animation,
                     curve: const Interval(.375, 1, curve: Curves.easeInOut),
                   );
           return FadeTransition(opacity: inT, child: child);
         },
       );
}
