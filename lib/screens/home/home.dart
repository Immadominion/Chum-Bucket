import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/wallet_provider.dart';
import 'package:chumbucket/screens/challenge_details_screen/challenge_details_screen.dart';
import 'package:chumbucket/screens/create_challenge_screen/create_challenge_screens.dart';
import 'package:chumbucket/screens/home/widgets/friends_tab.dart';
import 'package:chumbucket/screens/home/widgets/header.dart';
import 'package:chumbucket/screens/home/widgets/tab_bar.dart';
import 'package:chumbucket/screens/home/widgets/empty_challenges.dart';
import 'package:chumbucket/services/local_friends_service.dart';
import 'package:chumbucket/services/local_database_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabController;
  int _friendsRefreshKey = 0; // Key to force FriendsTab refresh
  int _challengesRefreshKey = 0; // Key to force challenges refresh

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);

    // Initialize wallet in the background when the app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuthAndWallet();
    });
  }

  // Initialize authentication and wallet in the background
  Future<void> _initializeAuthAndWallet() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Make sure auth is initialized
      if (!authProvider.isInitialized) {
        await authProvider.initialize();
      }

      // If authenticated, initialize the wallet
      if (authProvider.isAuthenticated) {
        final walletProvider = Provider.of<WalletProvider>(
          context,
          listen: false,
        );
        if (!walletProvider.isInitialized) {
          await walletProvider.initializeWallet(context);
        }
      }
    } catch (e) {
      debugPrint('Error initializing wallet in home screen: $e');
      // Don't show errors to users here as this is background initialization
    }
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chum Bucket'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Debug: Clear Database Button
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () => _showClearDatabaseDialog(),
            tooltip: 'Clear Database (Debug)',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            children: [
              friendsChallengeScreenHeader(context),
              SizedBox(height: 20.h),
              FriendsChallengeScreenTabBar(tabController: tabController),
              SizedBox(height: 10.h),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [
                    FriendsTab(
                      key: ValueKey(
                        _friendsRefreshKey,
                      ), // Force rebuild when friends change
                      createNewChallenge: createNewChallenge,
                      onFriendSelected: onFriendSelected,
                      buildViewMoreItem: buildViewMoreItem,
                    ),
                    buildPendingTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildViewMoreItem(BuildContext context, int remainingCount) {
    return Column(
      children: [
        Container(
          width: 80.w,
          height: 80.w,
          decoration: BoxDecoration(
            color: Color(0xFFE0E0FF),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '+$remainingCount',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6E6EFF),
              ),
            ),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'View More',
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget buildPendingTab() {
    return Consumer<WalletProvider>(
      key: ValueKey(_challengesRefreshKey), // Force rebuild when key changes
      builder: (context, walletProvider, child) {
        // Temporarily return challenges directly to test UI
        return FutureBuilder<List<dynamic>>(
          future: _getChallenges(walletProvider),
          builder: (context, snapshot) {
            print('🔍 Challenges tab state: ${snapshot.connectionState}');
            print('🔍 Has data: ${snapshot.hasData}');
            print('🔍 Data: ${snapshot.data}');

            if (snapshot.connectionState == ConnectionState.waiting) {
              print('🔍 Showing shimmer...');
              return _buildShimmerChallenges();
            } else if (snapshot.hasError) {
              print('🔍 Error: ${snapshot.error}');
              return Center(
                child: Text(
                  'Error loading challenges: ${snapshot.error}',
                  style: TextStyle(fontSize: 16.sp, color: Colors.red),
                ),
              );
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              print('🔍 No data, showing empty state');
              return const EmptyChallenges();
            } else {
              print('🔍 Showing ${snapshot.data!.length} challenges');
              return _buildChallengesList(snapshot.data!);
            }
          },
        );
      },
    );
  }

  Future<List<dynamic>> _getChallenges(WalletProvider walletProvider) async {
    try {
      // Get the current user's ID for filtering challenges
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null || walletProvider.challengeService == null) {
        print('🔍 No user or challenge service available');
        return [];
      }

      print('🔍 Fetching challenges from database for user: ${currentUser.id}');

      // Get challenges from the challenge service
      // This will fetch from the local database which should contain challenges
      // that were created via the Anchor program
      final challenges = await walletProvider.challengeService!.getChallenges(
        userId: currentUser.id,
      );

      print('🔍 Found ${challenges.length} challenges from database');

      // Convert Challenge objects to maps for the UI
      final challengesList =
          challenges.map((challenge) {
            return {
              'id': challenge.id,
              'friendName': challenge.participantEmail ?? 'Unknown',
              'amount': challenge.amount, // This is the correct property name
              'description': challenge.description,
              'status': challenge.status.toString().split('.').last,
              'createdAt': challenge.createdAt,
              'escrowAddress':
                  challenge
                      .multisigAddress, // This is the correct property name
              'vaultAddress': challenge.vaultAddress,
              'platformFee': challenge.platformFee,
              'winnerAmount': challenge.winnerAmount,
            };
          }).toList();

      return challengesList;
    } catch (e) {
      print('🔍 Error fetching challenges: $e');
      // Return empty list on error rather than throwing
      return [];
    }
  }

  Widget _buildShimmerChallenges() {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: _buildShimmerChallengeCard(),
        );
      },
    );
  }

  Widget _buildShimmerChallengeCard() {
    return Container(
      width: double.infinity,
      height: 80.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        color: Colors.transparent,
      ),
      child: Stack(
        children: [
          // Base gradient
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF5F5F5), Color(0xFFE8E8E8)],
              ),
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          // Shimmer animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: -1.0, end: 2.0),
            duration: const Duration(milliseconds: 1500),
            builder: (context, value, child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  gradient: LinearGradient(
                    begin: Alignment(value - 1.0, 0.0),
                    end: Alignment(value, 0.0),
                    colors: const [
                      Colors.transparent,
                      Colors.white24,
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
            onEnd: () {
              // Restart animation
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChallengesList(List<dynamic> challenges) {
    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: challenges.length,
      itemBuilder: (context, index) {
        final challenge = challenges[index];
        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: _buildChallengeCard(challenge),
        );
      },
    );
  }

  Widget _buildChallengeCard(Map<String, dynamic> challenge) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Friend avatar
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: const Color(0xFF6E6EFF),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                challenge['friendName'][0].toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Challenge details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  challenge['friendName'],
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  challenge['description'],
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Amount and status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${challenge['amount']} SOL',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF6E6EFF),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  challenge['status'],
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void onFriendSelected(String name, String walletAddress) async {
    // Determine avatar color based on name
    String avatarColor = _getAvatarColorForFriend(name);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CreateChallengeScreen(
              friendName: name,
              friendAddress:
                  walletAddress, // Now using real wallet address from local database
              friendAvatarColor: avatarColor,
            ),
      ),
    );

    if (result != null && mounted) {
      // Refresh challenges tab since a new challenge was created
      setState(() {
        _challengesRefreshKey++;
      });

      // Switch to challenges tab to show the new challenge
      tabController.animateTo(1);

      // If the challenge was created, open the challenge details screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => ChallengeDetailsScreen(
                friendName: result['friendName'],
                friendAvatarColor: avatarColor,
                userAvatarColor: '#FFBE55', // Default for now
                description: result['description'],
                amount: result['amount'],
              ),
        ),
      );
    }
  }

  void createNewChallenge() {
    showDialog(
      context: context,
      builder:
          (context) => _AddFriendDialog(
            onFriendAdded: () {
              // Refresh the friends tab by changing the key
              setState(() {
                _friendsRefreshKey++;
              });
            },
          ),
    );
  }

  void _showClearDatabaseDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Database'),
            content: const Text(
              'This will delete ALL data including friends, challenges, and other records. This action cannot be undone.\n\nAre you sure?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await LocalDatabaseService.clearAllData();
                    Navigator.pop(context);
                    setState(() {
                      _friendsRefreshKey++;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Database cleared successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error clearing database: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear Database'),
              ),
            ],
          ),
    );
  }

  String _getAvatarColorForFriend(String name) {
    // Simple mapping of friend names to colors
    final Map<String, String> colorMap = {
      'Zara': '#FFBE55',
      'Kito': '#FF5A55',
      'Milo': '#55A9FF',
      'Nia': '#FF55A9',
      'Rex': '#55FFBE',
    };

    return colorMap[name] ?? '#FFBE55'; // Default to first color if not found
  }
}

// Add Friend Dialog Widget
class _AddFriendDialog extends StatefulWidget {
  final VoidCallback onFriendAdded;

  const _AddFriendDialog({required this.onFriendAdded});

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();

    if (name.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Add friend to local database
      await LocalFriendsService.addFriend(
        userPrivyId: currentUser.id,
        friendName: name,
        friendWalletAddress: address,
      );

      widget.onFriendAdded(); // Refresh the friends list
      Navigator.pop(context);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name added as friend!')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding friend: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Friend'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Friend Name',
                hintText: 'Enter friend\'s name',
              ),
            ),
            SizedBox(height: 10.h),
            TextField(
              controller: _addressController,
              enabled: !_isLoading,
              decoration: const InputDecoration(
                labelText: 'Solana Address',
                hintText: 'Enter valid Solana wallet address',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isLoading ? null : _addFriend,
          child:
              _isLoading
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text('Add'),
        ),
      ],
    );
  }
}
