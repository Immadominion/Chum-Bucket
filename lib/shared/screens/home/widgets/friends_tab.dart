import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_preview.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';

import 'package:chumbucket/shared/widgets/widgets.dart';

class FriendsTab extends StatefulWidget {
  final VoidCallback createNewChallenge;
  final Function(String, String)
  onFriendSelected; // Now passes name and wallet address
  final Widget Function(BuildContext context, int remainingCount)
  buildViewMoreItem;
  final VoidCallback
  onViewAllChallenges; // New callback for viewing all challenges
  final Function(Map<String, dynamic>, bool) onMarkChallengeCompleted;

  const FriendsTab({
    super.key,
    required this.createNewChallenge,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    required this.onViewAllChallenges,
    required this.onMarkChallengeCompleted,
  });
  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  List<Map<String, String>> friends = [];
  bool isLoading = true;
  bool hasAttemptedLoad = false; // Track if we've tried to load

  @override
  void initState() {
    super.initState();
    // Don't load friends immediately - wait for auth state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFriendsWhenReady();
    });
  }

  Future<void> _loadFriendsWhenReady() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // If user is already available, load friends immediately
    if (authProvider.currentUser != null) {
      _loadFriends();
    } else {
      // Otherwise, wait for auth to be ready
      print('FriendsTab: Waiting for auth to be ready...');
      if (mounted) {
        setState(() => isLoading = true);
      }
    }
  }

  Future<void> _loadFriends() async {
    if (hasAttemptedLoad) return; // Prevent multiple load attempts

    try {
      if (mounted) {
        setState(() {
          isLoading = true;
          hasAttemptedLoad = true;
        });
      }
      print('FriendsTab: Starting to load friends...');

      // Get current user
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        print('FriendsTab: No current user found');
        if (mounted) {
          setState(() => isLoading = false);
        }
        return;
      }

      print('FriendsTab: Loading friends for user: ${currentUser.id}');

      // Load friends from Supabase
      final friendsData = await UnifiedDatabaseService.getUserFriends(
        currentUser.id,
        userPrivyId: currentUser.id,
      );

      // Convert to UI format expected by FriendsGrid
      final uiFriends =
          friendsData
              .map<Map<String, String>>(
                (friend) => {
                  'name': friend['name'] as String,
                  'walletAddress': friend['walletAddress'] as String,
                  'avatarColor': friend['avatarColor'] as String,
                  'imagePath': friend['imagePath'] as String,
                },
              )
              .toList();

      print('FriendsTab: Loaded ${uiFriends.length} friends from Supabase');
      for (final friend in uiFriends) {
        print('  - ${friend['name']} (${friend['walletAddress']})');
      }

      if (mounted) {
        setState(() {
          friends = uiFriends;
          isLoading = false;
        });
      }

      print('FriendsTab: UI updated with ${friends.length} friends');
    } catch (e) {
      print('Error loading friends: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Auto-load friends when user becomes available (only if we haven't attempted yet)
        if (authProvider.currentUser != null && !hasAttemptedLoad) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadFriends();
          });
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(16.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 10.h),
                    Text(
                      'Who do you want to challenge?',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // SizedBox(height: 8.h),
                    isLoading
                        ? Padding(
                          padding: EdgeInsets.only(top: 80.h, bottom: 20.h),
                          child: const LoadingIndicator(message: ''),
                        )
                        : FriendsGrid(
                          friends: friends,
                          onFriendSelected: (friendName) {
                            final friend = friends.firstWhere(
                              (f) => f['name'] == friendName,
                              orElse: () => {'walletAddress': ''},
                            );
                            // Pass raw wallet address; resolution will happen where displayed
                            widget.onFriendSelected(
                              friendName,
                              friend['walletAddress'] ?? '',
                            );
                          },
                          buildViewMoreItem: widget.buildViewMoreItem,
                          maxVisibleFriends:
                              5, // Show 5 friends before "View More"
                        ),
                    // SizedBox(height: 15.h),
                    ChallengeButton(
                      createNewChallenge: widget.createNewChallenge,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),
              Stack(
                children: [
                  Center(
                    child: Opacity(
                      opacity: 0.9,
                      child: Text(
                        'Challenges',
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: -2,
                    // bottom: 0,
                    child: GestureDetector(
                      onTap: widget.onViewAllChallenges,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 8.h,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View All',
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            SizedBox(width: 4.w),
                            PhosphorIcon(
                              PhosphorIconsRegular.arrowRight,
                              color: Colors.grey.shade700,
                              size: 18.sp,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              ChallengesPreview(
                onViewAll: widget.onViewAllChallenges,
                onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
              ),
            ],
          ),
        );
      },
    );
  }
}
