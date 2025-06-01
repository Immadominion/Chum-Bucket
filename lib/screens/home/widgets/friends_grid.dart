import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/screens/home/widgets/friend_item.dart';

class FriendsGrid extends StatelessWidget {
  final List<Map<String, String>> friends;
  final Function(String) onFriendSelected;
  final WidgetBuilder buildViewMoreItem;

  const FriendsGrid({
    Key? key,
    required this.friends,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12.w,
        mainAxisSpacing: 16.h,
        childAspectRatio: 0.9,
      ),
      itemCount: friends.length + 1,
      itemBuilder: (context, index) {
        if (index < friends.length) {
          return buildFriendItem(friends[index], onFriendSelected);
        } else {
          return buildViewMoreItem(context);
        }
      },
    );
  }
}