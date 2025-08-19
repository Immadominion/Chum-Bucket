import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class FriendsChallengeScreenTabBar extends StatefulWidget {
  final TabController tabController;

  const FriendsChallengeScreenTabBar({Key? key, required this.tabController})
    : super(key: key);

  @override
  State<FriendsChallengeScreenTabBar> createState() =>
      _FriendsChallengeScreenTabBarState();
}

class _FriendsChallengeScreenTabBarState
    extends State<FriendsChallengeScreenTabBar> {
  // Define the challenge button color (same as in ChallengeButton)
  static const Color challengeButtonColor = Color(0xFFFF5A76);

  @override
  void initState() {
    super.initState();
    // Listen to tab controller changes to rebuild the widget
    widget.tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => widget.tabController.animateTo(0),
          child: Row(
            children: [
              Text(
                'Friends',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w600,
                  color:
                      widget.tabController.index == 0
                          ? Colors.black
                          : Colors.grey,
                ),
              ),
              SizedBox(width: 4.w),
              // Show dot on Friends tab when Friends is active
              if (widget.tabController.index == 0)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: challengeButtonColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: 24.w),
        GestureDetector(
          onTap: () => widget.tabController.animateTo(1),
          child: Row(
            children: [
              Text(
                'Pending',
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w600,
                  color:
                      widget.tabController.index == 1
                          ? Colors.black
                          : Colors.grey,
                ),
              ),
              SizedBox(width: 4.w),
              // Show dot on Pending tab when Pending is active
              if (widget.tabController.index == 1)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: challengeButtonColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
