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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabController;

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
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Column(
            children: [
              friendsChallengeScreenHeader(context),
              SizedBox(height: 20.h),
              FriendsChallengeScreenTabBar(tabController),
              SizedBox(height: 10.h),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: [
                    FriendsTab(
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

  Widget buildViewMoreItem(BuildContext context) {
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
              '+12',
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
    return Center(
      child: Text(
        'No pending challenges',
        style: TextStyle(fontSize: 16.sp, color: Colors.grey),
      ),
    );
  }

  void onFriendSelected(String name) async {
    // Determine avatar color based on name
    String avatarColor = _getAvatarColorForFriend(name);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CreateChallengeScreen(
              friendName: name,
              friendAddress:
                  'solana_address_placeholder', // In a real app, this would come from your friend database
              friendAvatarColor: avatarColor,
            ),
      ),
    );

    if (result != null && mounted) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Add New Friend'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: 'Friend Name'),
                  ),
                  SizedBox(height: 10.h),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Solana Address',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Friend added!')),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
      );
    });
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
