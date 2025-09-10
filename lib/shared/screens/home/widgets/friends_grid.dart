import 'package:chumbucket/shared/screens/home/widgets/friend_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';


class FriendsGrid extends StatelessWidget {
  final List<Map<String, String>> friends;
  final Function(String) onFriendSelected;
  final Widget Function(BuildContext context, int remainingCount)
  buildViewMoreItem;
  final int maxVisibleFriends; // Maximum friends to show before "View More"

  const FriendsGrid({
    Key? key,
    required this.friends,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    this.maxVisibleFriends =
        5, // Default to 5 friends visible (2 rows of 3, minus 1 for view more)
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hasMoreFriends = friends.length > maxVisibleFriends;
    final visibleFriends =
        hasMoreFriends ? friends.take(maxVisibleFriends).toList() : friends;

    // Only add 1 to itemCount if there are more friends to show
    final itemCount =
        hasMoreFriends ? visibleFriends.length + 1 : visibleFriends.length;

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12.w,
        childAspectRatio: 0.9,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < visibleFriends.length) {
          return buildFriendItem(visibleFriends[index], onFriendSelected);
        } else {
          // This is the "View More" item - only shows when hasMoreFriends is true
          final remainingCount = friends.length - maxVisibleFriends;
          return buildViewMoreItem(context, remainingCount);
        }
      },
    );
  }
}
