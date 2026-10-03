/// The frame every full-screen onboarding step shares (onboarding spec §4.1):
/// a 56dp row with Back and the progress segments, content that scrolls (never
/// sized as a fraction of the screen), and a sticky action area that rides
/// above the keyboard with a hairline only when content scrolls under it.
/// No close button, anywhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class OnboardingScaffold extends StatefulWidget {
  const OnboardingScaffold({
    super.key,
    required this.children,
    this.header,
    this.onBack,
    this.busy = false,
    this.progress,
    this.actions = const [],
    this.footer,
    this.announce,
    this.controller,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  /// Full-bleed content above the gutters (the brand band). It paints under
  /// the status bar when there is no top row.
  final Widget? header;

  /// Content inside the 16dp gutters, centred at most 480dp wide.
  final List<Widget> children;

  /// Shows the back arrow (48dp target). Null: no arrow.
  final VoidCallback? onBack;

  /// While busy, Back does nothing (wallet or browser hand-off).
  final bool busy;

  /// "Step i of n", or null for steps without progress (W1, B1, U1, R).
  final ({int index, int total})? progress;

  /// The sticky area: a primary button, then text actions.
  final List<Widget> actions;

  /// A small line under the actions (W1's venue line).
  final Widget? footer;

  /// Announced once on entry, after "Step i of n." when there is progress.
  final String? announce;
  final ScrollController? controller;
  final EdgeInsets contentPadding;

  @override
  State<OnboardingScaffold> createState() => _OnboardingScaffoldState();
}

class _OnboardingScaffoldState extends State<OnboardingScaffold> {
  bool _contentUnder = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final title = widget.announce;
      final progress = widget.progress;
      if (title == null) return;
      final text =
          progress == null
              ? title
              : '${OnboardingCopy.stepOf(progress.index, progress.total)}. '
                  '$title';
      onbAnnounce(context, text);
    });
  }

  /// Only the page's own scroll decides the hairline: a horizontal strip
  /// inside the page (W1's live calls) reports its own metrics too, and its
  /// next card is not content under the actions.
  bool _onMetrics(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return false;
    final under = metrics.extentAfter > 0.5;
    if (under != _contentUnder) setState(() => _contentUnder = under);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final progress =
        widget.progress != null && widget.progress!.total > 1
            ? widget.progress
            : null;
    final hasTopRow = widget.onBack != null || progress != null;
    final keyboardOpen = media.viewInsets.bottom > 0;
    final bottomPad =
        keyboardOpen
            ? 12.0
            : (media.viewPadding.bottom < 16 ? 16.0 : media.viewPadding.bottom);

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) widget.header!,
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnbSpace.maxContentWidth,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                top: widget.contentPadding.top,
                bottom: widget.contentPadding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in widget.children)
                    child is OnbFullBleed
                        ? child.child
                        : Padding(
                          padding: EdgeInsets.only(
                            left: widget.contentPadding.left,
                            right: widget.contentPadding.right,
                          ),
                          child: child,
                        ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (!hasTopRow && widget.header == null) {
      content = SafeArea(bottom: false, child: content);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            if (hasTopRow)
              SafeArea(
                bottom: false,
                child: _TopRow(
                  onBack: widget.busy ? null : widget.onBack,
                  showBack: widget.onBack != null,
                  progress: progress,
                ),
              ),
            Expanded(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (n) => _onMetrics(n.metrics, n.depth),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) => _onMetrics(n.metrics, n.depth),
                  child: SingleChildScrollView(
                    controller: widget.controller,
                    child: content,
                  ),
                ),
              ),
            ),
            if (widget.actions.isNotEmpty || widget.footer != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border(
                    top: BorderSide(
                      color:
                          _contentUnder
                              ? AppColors.outlineVariant
                              : Colors.transparent,
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: OnbSpace.maxContentWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...widget.actions,
                          if (widget.footer != null) widget.footer!,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.onBack,
    required this.showBack,
    required this.progress,
  });

  final VoidCallback? onBack;
  final bool showBack;
  final ({int index, int total})? progress;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: [
        const SizedBox(width: 4),
        if (showBack)
          IconButton(
            key: const ValueKey('onboarding-back'),
            tooltip: OnboardingCopy.back,
            onPressed: onBack,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: BasilIcon(
              'arrow-left-outline',
              size: 24,
              color:
                  onBack == null
                      ? AppColors.textDisabled
                      : AppColors.textPrimary,
            ),
          )
        else
          const SizedBox(width: 48),
        const SizedBox(width: 8),
        Expanded(
          child:
              progress == null
                  ? const SizedBox.shrink()
                  : OnboardingProgress(
                    index: progress!.index,
                    total: progress!.total,
                  ),
        ),
        const SizedBox(width: 60),
      ],
    ),
  );
}

/// One segment per step in this run: 4dp tall, 4dp apart, done and current in
/// brand pink. Read as "Step i of n".
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.index,
    required this.total,
  });

  final int index;
  final int total;

  static const _track = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final reduce = onbReduceMotion(context);
    return Semantics(
      label: OnboardingCopy.stepOf(index, total),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: _track,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: AnimatedFractionallySizedBox(
                  duration:
                      reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  widthFactor: i <= index ? 1 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A step's title: a heading for screen readers, read first.
class OnbTitle extends StatelessWidget {
  const OnbTitle(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  /// Display titles already start at 28sp; past 1.4x a word like
  /// "Chumbucket" or "@username" no longer fits a 320dp line and breaks
  /// mid-word. Android 14 scales large text the same way (non-linearly:
  /// big type grows less than body type). Body text is never clamped.
  static const double maxTitleScale = 1.4;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: style ?? OnbText.title,
      textScaler: MediaQuery.textScalerOf(
        context,
      ).clamp(maxScaleFactor: maxTitleScale),
    ),
  );
}

/// A step's body line under its title.
class OnbBody extends StatelessWidget {
  const OnbBody(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: OnbText.body);
}

/// Content that runs edge to edge past the gutters (a horizontal strip).
class OnbFullBleed extends StatelessWidget {
  const OnbFullBleed({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
