import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/core/theme/app_colors.dart';

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
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.87;
    final minHeight = 450.h;
    final preferredHeight = 500.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(43.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Header with gradient background and wave
          Container(
            height: 180.h.clamp(140.h, maxHeight * 0.28),
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(43.r),
                topRight: Radius.circular(43.r),
              ),
            ),
            child: Stack(
              children: [
                // Gradient header
                Container(
                  width: double.infinity,
                  height: 150.h,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(43.r),
                      topRight: Radius.circular(43.r),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 8.h),
                      // Drag handle
                      Container(
                        width: 43.w,
                        height: 3.2.h,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                      SizedBox(height: 20.h),

                      SizedBox(height: 8.h),
                      // Main title
                      Text(
                        'All Friends',
                        style: TextStyle(
                          fontSize: 24.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      // Subtitle
                      Text(
                        'Select a friend to challenge',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // White wavy section with smooth waves
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ClipPath(
                    clipper: DetailedWaveClipper(),
                    child: Container(
                      height: 150.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            offset: const Offset(0, -2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Friends list with iOS-style circular scroll
          Positioned(
            top: 120.h,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scrollable friends list with iOS circular picker behavior
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _scrollAnimation,
                      builder: (context, child) {
                        return NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            // Add subtle feedback on scroll
                            if (notification is ScrollUpdateNotification) {
                              // Optional: Add haptic feedback or scroll indicators
                            }
                            return false;
                          },
                          child: Column(
                            children: [
                              // iOS Wheel Picker for friends
                              _buildFriendsGrid(),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsGrid() {
    // iOS-style circular wheel picker for friends
    return Container(
      height: 350.h, // Fixed height for the wheel picker
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      child: ListWheelScrollView.useDelegate(
        controller: _wheelController,
        itemExtent: 80.h, // Height of each friend item in the wheel
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
        margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          color: Colors.white,
          border: Border.all(color: Colors.grey.withOpacity(0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
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
                  color: Colors.grey.withOpacity(0.15),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
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
                      color: AppColors.primary.withOpacity(0.1),
                      child: Icon(
                        PhosphorIcons.user(),
                        size: 26.sp,
                        color: AppColors.primary.withOpacity(0.7),
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
                    friend['name'] ?? 'Friend',
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
                      Text(
                        'Available',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // iOS-style arrow indicator
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
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
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    elevation: 0,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
        child: SafeArea(
          child: ViewMoreFriendsSheet(
            friends: friends,
            onFriendSelected: onFriendSelected,
          ),
        ),
      );
    },
  );
}
