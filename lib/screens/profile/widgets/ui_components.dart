import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Gradient button used throughout the profile screen
Widget buildGradientButton({
  required String text,
  required VoidCallback onPressed,
  required IconData icon,
  required List<Color> gradientColors,
}) {
  return Container(
    height: 50.h,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(12.r),
    ),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 20.sp),
          SizedBox(width: 8.w),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Secondary button with outline style
Widget buildSecondaryButton({
  required String text,
  required VoidCallback onPressed,
  required IconData icon,
}) {
  return Container(
    height: 50.h,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12.r),
      border: Border.all(color: Colors.grey.shade300, width: 1),
    ),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20.sp),
          SizedBox(width: 8.w),
          Text(
            text,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

/// Menu tile component used in settings modal
Widget buildMenuTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  Color? iconColor,
  bool isDanger = false,
}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 16.h),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: isDanger ? Colors.red.withOpacity(0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color:
                isDanger
                    ? Colors.red.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: (iconColor ?? Colors.blue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
                icon,
                color: isDanger ? Colors.red : (iconColor ?? Colors.blue),
                size: 22.sp,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: isDanger ? Colors.red : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color:
                          isDanger
                              ? Colors.red.withOpacity(0.7)
                              : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDanger ? Colors.red.withOpacity(0.7) : Colors.grey,
              size: 20.sp,
            ),
          ],
        ),
      ),
    ),
  );
}
