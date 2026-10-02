import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';

/// The shared floating modal shell. Callers own content/actions, not gradients,
/// wave geometry, title measurement, keyboard offsets or dismissal chrome.
///
/// Geometry is the reference comp's
/// (`assets/images/open_sourced_design_inspiration/irfan/img2.jpeg`): 43dp
/// corners top and bottom (the original app's `43.r`), floating 10.5dp in from
/// each side, a soft neutral shadow.
///
/// There is no close button. The sheet closes by dragging the header down,
/// tapping the handle or the backdrop, or system Back. A busy sheet
/// ([canDismiss] false) refuses all four: dragging it gives a little and
/// springs back, so it reads as locked rather than broken.
class ChumbucketWavySheet extends StatefulWidget {
  const ChumbucketWavySheet({
    super.key,
    required this.title,
    required this.body,
    this.value,
    this.subtitle,
    this.maxHeight,
    this.headerLeading,
    this.headerLeadingDiameter = 92,
    this.footer,
    this.canDismiss = true,
    this.onClose,
    this.showHeader = true,
  });

  /// Without the brand header, for a body whose own top is the sheet's
  /// header — the receipt, whose pink scalloped hero is also the shared
  /// image. The handle, its 48dp Close target and drag-to-close stay; [title]
  /// stays as the sheet's accessible heading.
  final bool showHeader;

  final String title;

  /// The one number the sheet is about, if it has one. Promotes [title] to a
  /// caption above it — the comp's "Bet Amount" over "$20.0".
  final String? value;

  final String? subtitle;
  final Widget body;

  /// Optional ceiling, never a requested height. Bodies must shrink-wrap:
  /// use a SingleChildScrollView, or shrinkWrap: true for list/grid viewports.
  /// In a body Column use mainAxisSize.min + Flexible, not Expanded/Spacer.
  final double? maxHeight;

  /// Straddles the scallop, as the comp's avatars do.
  final Widget? headerLeading;

  /// The avatar circle's diameter inside [headerLeading].
  final double headerLeadingDiameter;
  final Widget? footer;
  final bool canDismiss;
  final VoidCallback? onClose;

  static const double radius = 43;

  /// Measured on the comp: 20px either side of a 742px-wide screen.
  static const double sideMargin = 10.5;

  @override
  State<ChumbucketWavySheet> createState() => _ChumbucketWavySheetState();
}

class _ChumbucketWavySheetState extends State<ChumbucketWavySheet>
    with SingleTickerProviderStateMixin {
  final _surface = GlobalKey();

  // Created eagerly. A lazy `late final` controller is first touched in
  // dispose() when the sheet was never dragged, which creates its ticker
  // against an already-deactivated element and throws on every close.
  late final AnimationController _settle;

  double _drag = 0;
  double _settleFrom = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_onSettleTick);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _close() {
    widget.onClose != null
        ? widget.onClose!()
        : Navigator.of(context).maybePop();
  }

  void _onSettleTick() {
    final t = Curves.easeOutCubic.transform(_settle.value);
    setState(() => _drag = _settleFrom * (1 - t));
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    _settle.stop();
    // A busy sheet only gives a little: it is locked, not broken.
    final resistance = widget.canDismiss ? 1.0 : .12;
    setState(() {
      _drag = math.max(0, _drag + (details.primaryDelta ?? 0) * resistance);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_closing) return;
    final height = _surface.currentContext?.size?.height ?? 400;
    final velocity = details.primaryVelocity ?? 0;
    if (widget.canDismiss && (_drag > height * .25 || velocity > 700)) {
      // The route's own exit animation carries the sheet out from here.
      _closing = true;
      _close();
      return;
    }
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: widget.canDismiss,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final top = media.viewPadding.top + 12;
          final bottom =
              math.max(media.viewInsets.bottom, media.viewPadding.bottom) + 14;
          final available = math.max(
            0.0,
            math.min(constraints.maxHeight, media.size.height) - top - bottom,
          );
          final heightLimit = math.min(
            widget.maxHeight ?? available,
            available,
          );
          // Land the sheet's edges on whole physical pixels. A half-pixel edge
          // lets composited content (the header) snap away from the clip, and
          // a 1px sliver of pink shows down one side.
          final side =
              (ChumbucketWavySheet.sideMargin * media.devicePixelRatio)
                  .roundToDouble() /
              media.devicePixelRatio;
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The floating sheet occupies a full-height route; handle the
                // exposed backdrop here instead of relying on the route barrier.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: widget.canDismiss ? _close : null,
                  ),
                ),
                AnimatedPadding(
                  duration:
                      media.disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Transform.translate(
                      offset: Offset(0, _drag),
                      child: Container(
                        key: _surface,
                        constraints: BoxConstraints(maxHeight: heightLimit),
                        width: double.infinity,
                        // Shadow only. The white is painted INSIDE the clip,
                        // with the content, so both share one geometry: a
                        // decoration painted outside the clip lands half a
                        // pixel off the clipped content on fractional edges,
                        // and the header's pink bleeds down one side.
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            ChumbucketWavySheet.radius,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .15),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            ChumbucketWavySheet.radius,
                          ),
                          child: ColoredBox(
                            color: AppColors.surface,
                            child: KeyedSubtree(
                              key: const ValueKey('chumbucket-sheet-surface'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.showHeader)
                                    // Dragging the header down closes the sheet.
                                    // Only the header: body scrolling and inputs keep
                                    // their own vertical gestures.
                                    GestureDetector(
                                      key: const ValueKey(
                                        'chumbucket-sheet-drag-region',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onVerticalDragUpdate: _onDragUpdate,
                                      onVerticalDragEnd: _onDragEnd,
                                      child: LayoutBuilder(
                                        builder: (context, headerConstraints) {
                                          final header = ChumbucketSheetHeader(
                                            title: widget.title,
                                            value: widget.value,
                                            subtitle: widget.subtitle,
                                            leading: widget.headerLeading,
                                            leadingAvatarDiameter:
                                                widget.headerLeadingDiameter,
                                            canClose: widget.canDismiss,
                                            onClose: _close,
                                          );
                                          // Titles wrap naturally. On very short
                                          // keyboard/landscape viewports the header
                                          // scrolls rather than starving the body.
                                          final maxHeight = heightLimit * .5;
                                          return header.naturalHeight(
                                                    context,
                                                    headerConstraints.maxWidth,
                                                  ) <=
                                                  maxHeight
                                              ? header
                                              : SizedBox(
                                                height: maxHeight,
                                                child: SingleChildScrollView(
                                                  child: header,
                                                ),
                                              );
                                        },
                                      ),
                                    ),
                                  Flexible(
                                    child: Material(
                                      color: AppColors.surface,
                                      child: TextButtonTheme(
                                        // The comp's secondary action: brand pink,
                                        // Inter SemiBold, no fill.
                                        data: TextButtonThemeData(
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppColors.primary,
                                            textStyle:
                                                AppTextStyles.sheetTextAction,
                                            minimumSize: const Size(48, 48),
                                          ),
                                        ),
                                        child: DefaultTextStyle(
                                          style: AppTextStyles
                                              .textTheme
                                              .bodyMedium!
                                              .copyWith(height: 1.5),
                                          child:
                                              widget.showHeader
                                                  ? widget.body
                                                  : _HeaderlessTop(
                                                    title: widget.title,
                                                    canClose: widget.canDismiss,
                                                    onClose: _close,
                                                    onDragUpdate: _onDragUpdate,
                                                    onDragEnd: _onDragEnd,
                                                    child: widget.body,
                                                  ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.footer != null)
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: heightLimit * .3,
                                      ),
                                      child: SingleChildScrollView(
                                        child: widget.footer!,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The header's handle, drag strip and Close target laid over a body that
/// supplies its own top.
class _HeaderlessTop extends StatelessWidget {
  const _HeaderlessTop({
    required this.title,
    required this.canClose,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.child,
  });

  final String title;
  final bool canClose;
  final VoidCallback onClose;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: title,
    explicitChildNodes: true,
    child: Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 48,
          child: GestureDetector(
            key: const ValueKey('chumbucket-sheet-drag-region'),
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: onDragUpdate,
            onVerticalDragEnd: onDragEnd,
            child: Align(
              alignment: Alignment.topCenter,
              child: Semantics(
                button: true,
                label: 'Close',
                enabled: canClose,
                onTap: canClose ? onClose : null,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('chumbucket-sheet-close-target'),
                  behavior: HitTestBehavior.opaque,
                  onTap: canClose ? onClose : null,
                  child: SizedBox(
                    width: 88,
                    height: 48,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        key: const ValueKey('chumbucket-sheet-handle'),
                        margin: const EdgeInsets.only(top: 7),
                        width: 38,
                        height: 2.8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<T?> showChumbucketWavySheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  // Preserve the status-bar inset; false strips it from the child's MediaQuery
  // before our keyboard-aware frame can account for it.
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  // The comp dims the app to ~188 grey from ~248: about a quarter black, with
  // the shell's own blur on top.
  barrierColor: Colors.black.withValues(alpha: .25),
  elevation: 0,
  showDragHandle: false,
  isDismissible: false,
  // The route's own swipe dismissal bypasses PopScope. The shell implements
  // its own drag on the header, which honours busy sheets.
  enableDrag: false,
  builder: builder,
);
