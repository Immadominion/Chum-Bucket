import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class HomeScreenTabBar extends StatefulWidget {
  final TabController tabController;

  const HomeScreenTabBar({Key? key, required this.tabController})
    : super(key: key);

  @override
  State<HomeScreenTabBar> createState() => _HomeScreenTabBarState();
}

class _HomeScreenTabBarState extends State<HomeScreenTabBar> {
  // Define the challenge button color (same as in ChallengeButton)
  static const Color challengeButtonColor = Color(0xFFFF5A76);
  static const List<String> _labels = ['Friends', 'Challenges', 'Arena'];

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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0) SizedBox(width: 16.w),
            GestureDetector(
              onTap: () => widget.tabController.animateTo(i),
              child: Row(
                children: [
                  Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color:
                          widget.tabController.index == i
                              ? Colors.black
                              : Colors.grey,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  if (widget.tabController.index == i)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: challengeButtonColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
