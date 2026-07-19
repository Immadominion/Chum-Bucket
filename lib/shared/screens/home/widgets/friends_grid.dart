import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/widgets/friend_item.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class FriendsGrid extends StatelessWidget {
  final List<Map<String, String>> friends;
  final Function(String) onFriendSelected;
  final Widget Function(BuildContext context, int remainingCount)
  buildViewMoreItem;
  final VoidCallback? onViewMorePressed;

  /// Opens the add-a-friend flow. When set, the empty state shows a real
  /// "Add a friend" button instead of a blank gap (H14).
  final VoidCallback? onAddFriend;
  final int maxVisibleFriends; // Maximum friends to show before "View More"

  const FriendsGrid({
    super.key,
    required this.friends,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    this.onViewMorePressed,
    this.onAddFriend,
    this.maxVisibleFriends =
        5, // Default to 5 friends visible (2 rows of 3, minus 1 for view more)
  });

  @override
  Widget build(BuildContext context) {
    // H14: a real empty state, not a blank 10px gap that reads as broken.
    if (friends.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18.h),
        child: Column(
          children: [
            BasilIcon(
              'user-plus-outline',
              size: 34.sp,
              color: AppColors.textTertiary,
            ),
            SizedBox(height: 10.h),
            Text(
              'No friends yet — add someone to challenge them',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            if (onAddFriend != null) ...[
              SizedBox(height: 12.h),
              OutlinedButton.icon(
                onPressed: onAddFriend,
                icon: BasilIcon(
                  'add-outline',
                  size: 16.sp,
                  color: AppColors.primary,
                ),
                label: Text(
                  'Add a friend',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

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
        childAspectRatio: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < visibleFriends.length) {
          return buildFriendItem(visibleFriends[index], onFriendSelected);
        } else {
          // This is the "View More" item - only shows when hasMoreFriends is true
          final remainingCount = friends.length - maxVisibleFriends;
          return GestureDetector(
            onTap: onViewMorePressed,
            child: buildViewMoreItem(context, remainingCount),
          );
        }
      },
    );
  }
}
