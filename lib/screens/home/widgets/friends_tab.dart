import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/screens/home/widgets/empty_challenges.dart';
import 'package:chumbucket/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/services/local_friends_service.dart';

class FriendsTab extends StatefulWidget {
  final VoidCallback createNewChallenge;
  final Function(String, String)
  onFriendSelected; // Now passes name and wallet address
  final Widget Function(BuildContext context, int remainingCount)
  buildViewMoreItem;

  const FriendsTab({
    super.key,
    required this.createNewChallenge,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
  });

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  List<Map<String, String>> friends = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      setState(() => isLoading = true);
      print('FriendsTab: Starting to load friends...');

      // Get current user
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        print('FriendsTab: No current user found');
        setState(() => isLoading = false);
        return;
      }

      print('FriendsTab: Loading friends for user: ${currentUser.id}');

      // Load friends from local database
      final friendsData = await LocalFriendsService.getFriends(currentUser.id);
      print('FriendsTab: Loaded ${friendsData.length} friends from database');

      // Convert to UI format
      final uiFriends = friendsData
          .map((friend) => LocalFriendsService.friendToUIFormat(friend))
          .toList();

      print('FriendsTab: Converted to UI format: ${uiFriends.length} friends');
      for (final friend in uiFriends) {
        print('  - ${friend['name']} (${friend['walletAddress']})');
      }

      setState(() {
        friends = uiFriends;
        isLoading = false;
      });

      print('FriendsTab: UI updated with ${friends.length} friends');
    } catch (e) {
      print('Error loading friends: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26.r),
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
              SizedBox(height: 10.h),
              Text(
                'Who do you want to challenge?',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 15.h),
              FriendsGrid(
                friends: friends,
                onFriendSelected: (friendName) {
                  // Find the friend's wallet address
                  final friend = friends.firstWhere(
                    (f) => f['name'] == friendName,
                    orElse: () => {'walletAddress': ''},
                  );
                  widget.onFriendSelected(
                    friendName,
                    friend['walletAddress'] ?? '',
                  );
                },
                buildViewMoreItem: widget.buildViewMoreItem,
                maxVisibleFriends: 5, // Show 5 friends before "View More"
              ),
              SizedBox(height: 15.h),
              ChallengeButton(createNewChallenge: widget.createNewChallenge),
            ],
          ),
        ),
        SizedBox(height: 24.h),
        Opacity(
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
        SizedBox(height: 12.h),
        Expanded(child: EmptyChallenges()),
      ],
    );
  }
}
