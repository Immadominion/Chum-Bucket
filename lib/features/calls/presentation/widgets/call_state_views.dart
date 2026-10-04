/// The states every surface in this slice must be able to reach: empty,
/// loading, offline, error and signed-out. (Stale is not a state the person
/// sees: saved content stays on screen and refreshes silently.)
///
/// They live in one file so they stay visually consistent and so a reviewer can
/// see at a glance that all of them exist and that none of them is a spinner
/// with no exit. The empty / error / offline / signed-out views are drawn by
/// the app-wide [ChumbucketStateView].
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

export 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';

/// Shared shell, drawn by the app-wide [ChumbucketStateView]: the art, ONE
/// short line ([title]) and at most one action. [message] is no longer drawn —
/// the owner asked for art and a line, not a paragraph — but screen readers
/// still hear it as a hint, so nothing a caller passes is lost.
class CallsStateView extends StatelessWidget {
  final String icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;
  final ChumbucketStateArtwork? artwork;

  const CallsStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent = AppColors.textTertiary,
    this.artwork,
  });

  @override
  Widget build(BuildContext context) {
    final art = artwork;
    return Center(
      child: SingleChildScrollView(
        child:
            art != null
                ? ChumbucketStateView(
                  artwork: art,
                  message: title,
                  semanticsHint: message.isEmpty ? null : message,
                  actionLabel: actionLabel,
                  onAction: onAction,
                )
                : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: BasilIcon(icon, size: 26, color: accent),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Semantics(
                        hint: message.isEmpty ? null : message,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'PPNeueMachina',
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: 20),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: ChumbucketPrimaryButton(
                            label: actionLabel!,
                            onPressed: onAction,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
      ),
    );
  }
}

/// Loading. Skeleton rows rather than a bare spinner so the shape of what is
/// coming is already visible.
class CallsLoadingView extends StatelessWidget {
  final int rows;

  const CallsLoadingView({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading calls',
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        itemCount: rows,
        separatorBuilder: (_, __) => SizedBox(height: 12.h),
        itemBuilder: (_, __) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height.h,
        decoration: BoxDecoration(
          color: AppColors.outlineVariant,
          borderRadius: BorderRadius.circular(6.r),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                decoration: const BoxDecoration(
                  color: AppColors.outlineVariant,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(child: bar(0.4, 12)),
            ],
          ),
          SizedBox(height: 14.h),
          bar(1, 12),
          SizedBox(height: 8.h),
          bar(0.7, 12),
        ],
      ),
    );
  }
}

/// Empty — loaded successfully, there is simply nothing here yet.
class CallsEmptyView extends StatelessWidget {
  final ChumbucketStateArtwork artwork;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CallsEmptyView({
    super.key,
    this.artwork = ChumbucketStateArtwork.calls,
    this.title = 'No calls yet',
    this.message =
        'When someone goes on record, their call shows up here — free, '
            'timestamped and locked.',
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => CallsStateView(
    icon: 'comment-outline',
    artwork: artwork,
    title: title,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Error — the request failed and there is nothing cached underneath. The
/// one line is the server's own short reason when it wrote one for people
/// ("This profile is private."), otherwise a plain "Couldn't load this".
class CallsErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const CallsErrorView({super.key, required this.message, this.onRetry});

  /// Longer than this, a reason is read to screen readers, not drawn.
  static const int _maxLine = 90;

  static final RegExp _machinery = RegExp(
    r'[:{}\[\]()_<>=/\\]|\d{3}|[a-z]\.[a-z]',
  );
  static final RegExp _transportWords = RegExp(
    r'\b(server|envelope|status|exception|null|undefined|json|trpc|'
    r'procedure|http|socket|stack)\b',
    caseSensitive: false,
  );

  /// Whether [reason] was written for a person: a sentence, not the transport
  /// describing itself (procedure paths like `calls.feed`, status codes, enum
  /// codes, "the server sent an empty envelope…"). Those are never the line,
  /// and never read to a screen reader either.
  static bool isHumanReason(String reason) =>
      reason.isNotEmpty &&
      RegExp(r'^[A-Z]').hasMatch(reason) &&
      !_machinery.hasMatch(reason) &&
      !_transportWords.hasMatch(reason);

  @override
  Widget build(BuildContext context) {
    final reason = message.trim();
    final human = isHumanReason(reason);
    final short = human && reason.length <= _maxLine;
    return CallsStateView(
      icon: 'info-triangle-outline',
      artwork: ChumbucketStateArtwork.error,
      accent: AppColors.error,
      title: short ? reason : 'Couldn\u2019t load this',
      message: short || !human ? '' : reason,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// Offline with nothing cached.
class CallsOfflineView extends StatelessWidget {
  final VoidCallback? onRetry;

  const CallsOfflineView({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => CallsStateView(
    icon: 'cloud-off-outline',
    artwork: ChumbucketStateArtwork.offline,
    accent: AppColors.warning,
    title: 'You\'re offline',
    message: 'Nothing is lost while you\'re away.',
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// Signed out. Reading is fine; this only gates writing, and it asks for an
/// account — never a wallet.
class CallsSignedOutView extends StatelessWidget {
  /// The one line on screen. Say what signing in is for here.
  final String title;

  /// Read to screen readers with [title].
  final String message;
  final VoidCallback? onSignIn;

  const CallsSignedOutView({
    super.key,
    this.title = 'Sign in to make a call',
    this.message =
        'Sign in to go on record. No wallet, no money — just your call, '
            'timestamped.',
    this.onSignIn,
  });

  @override
  Widget build(BuildContext context) => CallsStateView(
    icon: 'user-outline',
    artwork: ChumbucketStateArtwork.access,
    title: title,
    message: message,
    actionLabel: onSignIn == null ? null : 'Sign in',
    onAction: onSignIn,
  );
}

/// A thin inline banner for the few facts that must sit above content, such
/// as demo data. Staleness is never one of them: the app refreshes on its own
/// and does not narrate it ("last updated…", "Refresh") — see
/// `ChumbucketStateView`'s rules. Offline with saved content is a small pill,
/// not a banner, and has no retry: the next open, resume or pull refreshes.
class CallsNotice extends StatelessWidget {
  final String icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool _pill;

  const CallsNotice({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
  }) : _pill = false;

  const CallsNotice._pill()
    : icon = 'cloud-off-outline',
      message = 'Offline',
      color = AppColors.warning,
      actionLabel = null,
      onAction = null,
      _pill = true;

  /// Content is on screen but it is saved, not live. [onRetry] is accepted
  /// for older callers and ignored: there is no retry button.
  factory CallsNotice.offline({VoidCallback? onRetry}) =>
      const CallsNotice._pill();

  /// Demo (fixture) venue data. Never allowed to present as a live result.
  factory CallsNotice.demoData() => const CallsNotice(
    icon: 'info-triangle-outline',
    message: 'Demo catalog data. This is sample data, not a live market.',
    color: AppColors.tertiary,
  );

  @override
  Widget build(BuildContext context) {
    if (_pill) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
        child: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: ChumbucketOfflinePill(),
        ),
      );
    }
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          BasilIcon(icon, size: 16.w, color: color),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.sp,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
