import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_header.dart';

/// The shared floating modal shell. Callers own content/actions, not gradients,
/// wave geometry, title measurement, keyboard offsets or dismissal chrome.
class ChumbucketWavySheet extends StatelessWidget {
  const ChumbucketWavySheet({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.height,
    this.headerLeading,
    this.footer,
    this.canDismiss = true,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final double? height;
  final Widget? headerLeading;
  final Widget? footer;
  final bool canDismiss;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: canDismiss,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final top = media.viewPadding.top + 12;
          final bottom =
              math.max(media.viewInsets.bottom, media.viewPadding.bottom) + 14;
          final available = math.max(
            0.0,
            math.min(constraints.maxHeight, media.size.height) - top - bottom,
          );
          final sheetHeight = math.min(
            height ?? media.size.height * .72,
            available,
          );
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
                    onTap:
                        canDismiss
                            ? onClose ?? () => Navigator.of(context).maybePop()
                            : null,
                  ),
                ),
                AnimatedPadding(
                  duration:
                      media.disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.fromLTRB(12, top, 12, bottom),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: sheetHeight,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .3),
                            blurRadius: 44,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          // Titles wrap naturally. On very short keyboard/landscape
                          // viewports the header can scroll without starving the body.
                          LayoutBuilder(
                            builder: (context, headerConstraints) {
                              final header = ChumbucketSheetHeader(
                                title: title,
                                subtitle: subtitle,
                                leading: headerLeading,
                                canClose: canDismiss,
                                onClose: onClose,
                              );
                              final maxHeight = sheetHeight * .5;
                              return header.naturalHeight(
                                        context,
                                        headerConstraints.maxWidth,
                                      ) <=
                                      maxHeight
                                  ? header
                                  : SizedBox(
                                    height: maxHeight,
                                    child: SingleChildScrollView(child: header),
                                  );
                            },
                          ),
                          Expanded(
                            child: Material(
                              color: AppColors.surface,
                              child: DefaultTextStyle(
                                style: AppTextStyles.textTheme.bodyMedium!
                                    .copyWith(height: 1.5),
                                child: body,
                              ),
                            ),
                          ),
                          if (footer != null)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: sheetHeight * .3,
                              ),
                              child: SingleChildScrollView(child: footer!),
                            ),
                        ],
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
  barrierColor: Colors.black.withValues(alpha: .45),
  elevation: 0,
  showDragHandle: false,
  isDismissible: false,
  // Swipe dismissal bypasses PopScope on a ModalBottomSheetRoute. Use the
  // shared close action, system Back, or guarded backdrop so busy guards hold.
  enableDrag: false,
  builder: builder,
);
