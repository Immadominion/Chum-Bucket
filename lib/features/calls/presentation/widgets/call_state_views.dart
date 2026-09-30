/// The six states every surface in this slice must be able to reach:
/// empty, loading, stale, offline, error and signed-out.
///
/// They live in one file so they stay visually consistent and so a reviewer can
/// see at a glance that all six exist and that none of them is a spinner with
/// no exit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Shared shell: icon, headline, one explanatory line, at most one action.
class CallsStateView extends StatelessWidget {
  final String icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;

  const CallsStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent = AppColors.textTertiary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 28.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: BasilIcon(icon, size: 26.w, color: accent),
                ),
              ),
              SizedBox(height: 14.h),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.sp,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: 16.h),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB8173B),
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.symmetric(
                      horizontal: 18.w,
                      vertical: 10.h,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  child: Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
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
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CallsEmptyView({
    super.key,
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
    title: title,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Error — the request failed and there is nothing cached underneath.
class CallsErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const CallsErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => CallsStateView(
    icon: 'info-triangle-outline',
    accent: AppColors.error,
    title: 'That didn\'t load',
    message: message,
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// Offline with nothing cached.
class CallsOfflineView extends StatelessWidget {
  final VoidCallback? onRetry;

  const CallsOfflineView({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => CallsStateView(
    icon: 'cloud-off-outline',
    accent: AppColors.warning,
    title: 'You\'re offline',
    message:
        'We can\'t reach anything right now. Your calls are safe — nothing is '
        'lost while you\'re away.',
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// Signed out. Reading is fine; this only gates writing, and it asks for an
/// account — never a wallet.
class CallsSignedOutView extends StatelessWidget {
  final String message;
  final VoidCallback? onSignIn;

  const CallsSignedOutView({
    super.key,
    this.message =
        'Sign in to go on record. No wallet, no money — just your call, '
            'timestamped.',
    this.onSignIn,
  });

  @override
  Widget build(BuildContext context) => CallsStateView(
    icon: 'user-outline',
    title: 'Sign in to make a call',
    message: message,
    actionLabel: onSignIn == null ? null : 'Sign in',
    onAction: onSignIn,
  );
}

/// A thin inline banner. Used for the stale, offline-with-cache and demo-data
/// notices that sit above content rather than replacing it.
class CallsNotice extends StatelessWidget {
  final String icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CallsNotice({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  /// Content is on screen but older than the provider's staleness window.
  factory CallsNotice.stale({
    required String message,
    VoidCallback? onRefresh,
  }) => CallsNotice(
    icon: 'clock-outline',
    message: message,
    color: AppColors.warning,
    actionLabel: onRefresh == null ? null : 'Refresh',
    onAction: onRefresh,
  );

  /// Content is on screen but it is cached, not live.
  factory CallsNotice.offline({VoidCallback? onRetry}) => CallsNotice(
    icon: 'cloud-off-outline',
    message: 'Offline — showing what we already had.',
    color: AppColors.warning,
    actionLabel: onRetry == null ? null : 'Retry',
    onAction: onRetry,
  );

  /// Demo (fixture) venue data. Never allowed to present as a live result.
  factory CallsNotice.demoData() => const CallsNotice(
    icon: 'info-triangle-outline',
    message: 'Demo catalog data. This is sample data, not a live market.',
    color: AppColors.tertiary,
  );

  @override
  Widget build(BuildContext context) {
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
