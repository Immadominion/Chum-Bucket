import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/widgets/friend_avatar.dart';

class FriendAvatarSection extends StatelessWidget {
  final String friendName;
  final String friendAvatarColor;
  final double size;

  const FriendAvatarSection({
    super.key,
    required this.friendName,
    required this.friendAvatarColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FriendAvatar(
          name: friendName,
          colorHex: friendAvatarColor,
          onTap: () {},
          size: size,
        ),
        SizedBox(height: 12.h),
        Text(
          friendName[0].toUpperCase() + friendName.substring(1),
          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
