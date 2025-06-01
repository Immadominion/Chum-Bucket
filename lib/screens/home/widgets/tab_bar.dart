import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

Widget FriendsChallengeScreenTabBar(TabController tabController) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      GestureDetector(
        onTap: () => tabController.animateTo(0),
        child: Text(
          'Friends',
          style: TextStyle(
            fontSize: 22.sp,
            fontWeight: FontWeight.w600,
            color: tabController.index == 0 ? Colors.black : Colors.grey,
          ),
        ),
      ),
      SizedBox(width: 24.w),
      GestureDetector(
        onTap: () => tabController.animateTo(1),
        child: Row(
          children: [
            Text(
              'Pending',
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.w600,
                color: tabController.index == 1 ? Colors.black : Colors.grey,
              ),
            ),
            SizedBox(width: 4.w),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
