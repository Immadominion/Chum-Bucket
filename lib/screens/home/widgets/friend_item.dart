import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/widgets/friend_avatar.dart';

Widget buildFriendItem(Map<String, String> friend, onFriendSelected) {
  return Column(
    children: [
      FriendAvatar(
        name: friend['name']!,
        colorHex: friend['avatarColor']!,
        imagePath: friend['imagePath'],
        onTap: () => onFriendSelected(friend['name']!),
        size: 90.sp,
      ),
      SizedBox(height: 8.h),
      Text(
        friend['name']!,
        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
