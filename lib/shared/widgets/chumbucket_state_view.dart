/// The one empty / error / offline / signed-out screen for the whole app:
/// brand art, one short line, at most one action.
///
/// Every list in the app reaches the same handful of states, and each used to
/// draw its own: a wall of explanatory text with a "Retry" text button, a
/// headline plus a paragraph, a bordered row. This replaces them with a single
/// look the owner asked for — the Plankton / Karen scene says what happened,
/// one line names it, and one button (only when there is something to do)
/// does it.
///
/// Rules (see `docs/design/state-art.md`):
///
/// * one short line — no paragraph underneath. Anything a screen reader needs
///   beyond it goes in [semanticsHint], never on screen;
/// * at most one action, drawn with the app's primary button so it reads as
///   the obvious next step, never a text link lost in copy;
/// * a loading state is not this. A spinner or skeleton keeps that job.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

export 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

class ChumbucketStateView extends StatelessWidget {
  const ChumbucketStateView({
    super.key,
    required this.artwork,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.semanticsHint,
    this.compact = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
  });

  /// The scene. Decorative: [message] carries the meaning.
  final ChumbucketStateArtwork artwork;

  /// The one short line, e.g. "No activity yet".
  final String message;

  /// The single action. Both must be set for a button to show.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A Basil icon name drawn before [actionLabel].
  final String? actionIcon;

  /// Extra context for screen readers only.
  final String? semanticsHint;

  /// 96dp art for a state inside a card, a sheet or a tab section; 144dp for
  /// a whole screen.
  final bool compact;

  final EdgeInsetsGeometry padding;

  bool get _hasAction => actionLabel != null && onAction != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          compact
              ? ChumbucketStateArt.compact(artwork)
              : ChumbucketStateArt(artwork),
          SizedBox(height: compact ? 10 : 14),
          Semantics(
            hint: semanticsHint,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'PPNeueMachina',
                color: AppColors.textPrimary,
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
          if (_hasAction) ...[
            SizedBox(height: compact ? 14 : 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: ChumbucketPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                leading:
                    actionIcon == null
                        ? null
                        : BasilIcon(
                          actionIcon!,
                          size: 18,
                          color: AppColors.onPrimary,
                        ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A [ChumbucketStateView] that fills whatever space it is given, centred,
/// and still scrolls — so it can sit under a `RefreshIndicator` and be pulled
/// to refresh like the list it stands in for.
class ChumbucketStateFill extends StatelessWidget {
  const ChumbucketStateFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// The only trace of "offline" a screen with saved content shows: a small
/// pill, no banner, no retry button. The app refreshes on its own when the
/// connection comes back (resume, pull-to-refresh, the next open).
class ChumbucketOfflinePill extends StatelessWidget {
  const ChumbucketOfflinePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Offline. Showing what was saved on this phone.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BasilIcon(
              'cloud-off-outline',
              size: 14,
              color: AppColors.onWarningContainer,
            ),
            SizedBox(width: 5),
            Text(
              'Offline',
              style: TextStyle(
                color: AppColors.onWarningContainer,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
