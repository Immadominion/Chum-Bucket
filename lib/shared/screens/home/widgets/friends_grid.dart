import 'package:flutter/material.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/screens/home/widgets/friend_item.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class FriendsGrid extends StatelessWidget {
  final List<Map<String, String>> friends;
  final Function(String) onFriendSelected;
  final Widget Function(BuildContext, int) buildViewMoreItem;
  final VoidCallback? onViewMorePressed;
  final VoidCallback? onAddFriend;
  final int maxVisibleFriends;
  const FriendsGrid({
    super.key,
    required this.friends,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    this.onViewMorePressed,
    this.onAddFriend,
    this.maxVisibleFriends = 5,
  });

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    if (friends.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const BasilIcon(
              'user-plus-outline',
              size: 40,
              color: AppColors.textPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Bring your people',
              style: styles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a friend to keep the conversation going.',
              textAlign: TextAlign.center,
              style: styles.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (onAddFriend != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: AppColors.textPrimary,
                ),
                onPressed: onAddFriend,
                child: const Text('Add a friend'),
              ),
            ],
          ],
        ),
      );
    }
    final visible = friends.take(maxVisibleFriends).toList();
    final remaining = friends.length - visible.length;
    // Wrap provides intrinsic height: names and 200% text never fit into a
    // fixed square. Keep the familiar three columns, two for larger text.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(14) > 21 ? 2 : 3;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final friend in visible)
              SizedBox(
                width: width,
                child: buildFriendItem(friend, onFriendSelected),
              ),
            if (remaining > 0)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  label: 'View $remaining more friends',
                  child: InkWell(
                    onTap: onViewMorePressed,
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 100),
                      child: buildViewMoreItem(context, remaining),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
