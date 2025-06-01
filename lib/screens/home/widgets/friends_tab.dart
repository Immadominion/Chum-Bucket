import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/screens/home/widgets/challenge_button.dart';
import 'package:recess/screens/home/widgets/empty_challenges.dart';
import 'package:recess/screens/home/widgets/friends_grid.dart';

class FriendsTab extends StatelessWidget {
  final VoidCallback createNewChallenge;
  final Function(String) onFriendSelected;
  final WidgetBuilder buildViewMoreItem;

  const FriendsTab({
    super.key,
    required this.createNewChallenge,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
  });

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> friends = [
      {
        'name': 'Zara',
        'avatarColor': '#FFBE55',
        'imagePath': 'assets/images/ai_gen/profile_images/1.png',
      },
      {
        'name': 'Kito',
        'avatarColor': '#FF5A55',
        'imagePath': 'assets/images/ai_gen/profile_images/2.png',
      },
      {
        'name': 'Milo',
        'avatarColor': '#55A9FF',
        'imagePath': 'assets/images/ai_gen/profile_images/3.png',
      },
      {
        'name': 'Nia',
        'avatarColor': '#FF55A9',
        'imagePath': 'assets/images/ai_gen/profile_images/4.png',
      },
      {
        'name': 'Rex',
        'avatarColor': '#55FFBE',
        'imagePath': 'assets/images/ai_gen/profile_images/5.png',
      },
    ];

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 16.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Who do you want to challenge?',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 20.h),
              FriendsGrid(
                friends: friends,
                onFriendSelected: onFriendSelected,
                buildViewMoreItem: buildViewMoreItem,
              ),
              SizedBox(height: 20.h),
              ChallengeButton(createNewChallenge: createNewChallenge),
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Opacity(
          opacity: 0.4,
          child: Text(
            'Challenges',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ),
        SizedBox(height: 12.h),
        Expanded(child: EmptyChallenges()),
      ],
    );
  }
}
