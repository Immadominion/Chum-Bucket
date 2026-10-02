import 'package:chumbucket/core/crash/crash_reporting.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The "Share crash reports" switch in Settings.
///
/// Styled like `ProfileMenuItem` so it sits in the same list. The whole row
/// toggles, and the switch carries the semantics, so it reads correctly to a
/// screen reader.
class CrashReportsSettingTile extends StatelessWidget {
  const CrashReportsSettingTile({super.key, CrashReporting? reporting})
    : _reporting = reporting;

  final CrashReporting? _reporting;

  @override
  Widget build(BuildContext context) {
    final reporting = _reporting ?? CrashReporting.instance;
    return ListenableBuilder(
      listenable: reporting,
      builder: (context, _) {
        final on = reporting.optedIn;
        final subtitle =
            on
                ? (reporting.canReport
                    ? 'On. Crash details help us fix bugs. No name or wallet is attached.'
                    : 'On. This build does not send reports.')
                : 'Off. Nothing is sent unless you turn this on.';
        return Container(
          margin: EdgeInsets.only(bottom: 8.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26.r),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.2),
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26.r),
              onTap: () => reporting.setOptedIn(!on),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(4.r),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(25.r),
                      ),
                      child: BasilIcon(
                        'shield-outline',
                        size: 26.r,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Share crash reports',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Switch.adaptive(
                      value: on,
                      activeTrackColor: AppColors.primary,
                      onChanged: reporting.setOptedIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
