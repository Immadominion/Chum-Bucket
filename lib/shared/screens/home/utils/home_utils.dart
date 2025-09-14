import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class HomeUtils {
  /// Get avatar color for friend based on name
  static String getAvatarColorForFriend(String name) {
    // Simple mapping of friend names to colors
    final Map<String, String> colorMap = {
      'Zara': '#FFBE55',
      'Kito': '#FF5A55',
      'Milo': '#55A9FF',
      'Nia': '#FF55A9',
      'Rex': '#55FFBE',
    };

    return colorMap[name] ?? '#FFBE55'; // Default to first color if not found
  }

  /// Build view more item widget
  static Widget buildViewMoreItem(
    BuildContext context,
    int remainingCount, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 75.w,
            height: 75.w,
            decoration: BoxDecoration(
              color: Color(0xFFE0E0FF),
              shape: BoxShape.circle,
              boxShadow:
                  onTap != null
                      ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ]
                      : null,
            ),
            child: Center(
              child: Text(
                '+$remainingCount',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6E6EFF),
                ),
              ),
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            'View More',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: onTap != null ? Color(0xFF6E6EFF) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
