import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Modal bottom sheet for viewing all friends with iOS circular picker-style animation
class ViewMoreFriendsSheet extends StatefulWidget {
  final List<Map<String, String>> friends;
  final Function(String) onFriendSelected;

  const ViewMoreFriendsSheet({
    super.key,
    required this.friends,
    required this.onFriendSelected,
  });

  @override
  State<ViewMoreFriendsSheet> createState() => _ViewMoreFriendsSheetState();
}

class _ViewMoreFriendsSheetState extends State<ViewMoreFriendsSheet>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scrollAnimation;
  late FixedExtentScrollController _wheelController;

  @override
  void initState() {
    super.initState();

    // Initialize wheel scroll controller for iOS picker effect
    _wheelController = FixedExtentScrollController();

    // Create subtle bounce animation for wheel scroll interaction
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scrollAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCirc),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _wheelController.dispose();
    super.dispose();
  }

  void _onFriendTap(String friendName) {
    // Quick haptic feedback for iOS-style interaction
    _animationController.forward().then((_) {
      _animationController.reverse();
    });

    // Close modal first, then call callback after a short delay
    Navigator.of(context).pop();

    // Small delay to ensure modal is fully closed before navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onFriendSelected(friendName);
    });
  }

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'All Friends',
    subtitle: 'Select a friend to challenge',
    body: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child:
          widget.friends.isEmpty
              ? const Text('Your friends will appear here.')
              : SizedBox(
                // A wheel needs a bounded viewport. Size it to the actual rows
                // (up to three), with room for the selected row's magnification.
                height:
                    (64 + MediaQuery.textScalerOf(context).scale(40)) *
                    widget.friends.length.clamp(1, 3) *
                    1.15,
                child: AnimatedBuilder(
                  animation: _scrollAnimation,
                  builder: (context, child) => _buildFriendsGrid(),
                ),
              ),
    ),
  );

  Widget _buildFriendsGrid() {
    // iOS-style circular wheel picker for friends
    return Container(
      padding: EdgeInsets.zero,
      child: ListWheelScrollView.useDelegate(
        controller: _wheelController,
        itemExtent: 64 + MediaQuery.textScalerOf(context).scale(40),
        diameterRatio: 1.8, // Controls the curvature - larger = flatter
        perspective: 0.004, // 3D perspective effect for depth
        offAxisFraction: 0.0, // Keep items centered horizontally
        physics: const FixedExtentScrollPhysics(), // iOS-style scroll behavior
        squeeze: 1.0, // No compression of items
        useMagnifier: true, // Magnify the center item
        magnification: 1.15, // 15% magnification for center item
        overAndUnderCenterOpacity: 0.7, // Fade non-center items
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            if (index < 0 || index >= widget.friends.length) {
              return null;
            }
            final friend = widget.friends[index];
            return _buildWheelFriendItem(friend, index);
          },
          childCount: widget.friends.length,
        ),
      ),
    );
  }

  Widget _buildWheelFriendItem(Map<String, String> friend, int index) {
    return GestureDetector(
      onTap: () => _onFriendTap(friend['name'] ?? ''),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          color: Colors.white,
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.12),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              offset: const Offset(0, 2),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            // Friend avatar optimized for horizontal layout
            Container(
              width: 52.w,
              height: 52.w,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26.r),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.15),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    offset: const Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.r),
                child: Image.asset(
                  friend['imagePath'] ??
                      'assets/images/ai_gen/profile_images/1.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      child: BasilIcon(
                        'user-outline',
                        size: 26.sp,
                        color: AppColors.primary.withValues(alpha: 0.7),
                      ),
                    );
                  },
                ),
              ),
            ),

            SizedBox(width: 16.w),

            // Friend info section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Friend name
                  Text(
                    friend['xLabel'] ?? friend['name'] ?? 'Friend',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  SizedBox(height: 2.h),

                  // Status with online indicator
                  Row(
                    children: [
                      Container(
                        width: 8.w,
                        height: 8.w,
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Flexible(
                        child: Text(
                          'Available',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // iOS-style arrow indicator
            BasilIcon(
              'caret-right-solid',
              size: 16.sp,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show the ViewMoreFriends modal
Future<void> showViewMoreFriendsSheet(
  BuildContext context, {
  required List<Map<String, String>> friends,
  required Function(String) onFriendSelected,
}) => showChumbucketWavySheet<void>(
  context: context,
  builder:
      (_) => ViewMoreFriendsSheet(
        friends: friends,
        onFriendSelected: onFriendSelected,
      ),
);
