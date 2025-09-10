import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/widgets/friend_avatar.dart';

Widget buildFriendItem(Map<String, String> friend, onFriendSelected) {
  return Column(
    mainAxisSize: MainAxisSize.min, // Use minimum space needed
    children: [
      Flexible(
        // Make avatar flexible instead of fixed size
        flex: 3,
        child: FriendAvatar(
          name: friend['name']!,
          colorHex: friend['avatarColor']!,
          imagePath: friend['imagePath'],
          onTap: () => onFriendSelected(friend['name']!),
          size: 75.sp, // Reduced from 90.sp
        ),
      ),
      SizedBox(height: 6.h), // Reduced from 8.h
      Flexible(
        // Make text flexible
        flex: 1,
        child: Text(
          friend['name']!,
          style: TextStyle(
            fontSize: 12.sp, // Reduced from 14.sp
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}
