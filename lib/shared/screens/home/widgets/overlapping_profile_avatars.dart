import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Widget that displays overlapping profile avatars for the resolve challenge sheet
/// The right image has full border, the left image has a custom clipped border
/// to create the illusion of being underneath at the intersection point
class OverlappingProfileAvatars extends StatelessWidget {
  final String userImagePath;
  final String friendImagePath;
  final String friendDisplayName;

  const OverlappingProfileAvatars({
    super.key,
    required this.userImagePath,
    required this.friendImagePath,
    required this.friendDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // User avatar (left) - with custom clipped border
        Column(
          children: [
            Stack(
              children: [
                // The image itself
                Container(
                  width: 95.w,
                  height: 95.h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: ClipOval(
                    child: Image.asset(userImagePath, fit: BoxFit.cover),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              'You',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
        // Friend avatar (right) - with full border, positioned to overlap
        Transform.translate(
          offset: Offset(-16.w, 0),
          child: Column(
            children: [
              Container(
                width: 95.w,
                height: 95.h,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: ClipOval(
                  child: Image.asset(friendImagePath, fit: BoxFit.cover),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                friendDisplayName,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
