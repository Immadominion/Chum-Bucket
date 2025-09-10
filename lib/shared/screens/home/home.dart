import 'package:chumbucket/features/challenges/presentation/screens/challenge_details_screen/challenge_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/create_challenge_screens.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/screens/home/widgets/tab_bar.dart';
import 'package:chumbucket/shared/screens/home/utils/home_utils.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';

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
  bool _isRefreshing = false;

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
      AppLogger.error('Error initializing wallet in home screen: $e');
      // Don't show errors to users here as this is background initialization
    }
  }

  Future<void> _onPullToRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      // Bump keys first so UI (including shimmers) updates immediately
      _friendsRefreshKey++;
      _challengesRefreshKey++;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final currentUser = authProvider.currentUser;

      if (currentUser != null) {
        String? address = walletProvider.walletAddress;
        // If wallet not ready, try to initialize it so we can sync
        if (address == null && !walletProvider.isInitialized) {
          await walletProvider.initializeWallet(context);
          address = walletProvider.walletAddress;
        }

        if (address != null) {
          await EfficientSyncService.instance.forceBlockchainSync(
            userId: currentUser.id,
            walletAddress: address,
          );
        }
      }
    } catch (e) {
      AppLogger.error('Home pull-to-refresh error: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
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
        child: RefreshIndicator(
          onRefresh: _onPullToRefresh,
          color: Theme.of(context).primaryColor,
          notificationPredicate: (_) => true, // Listen to nested scrollables
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Column(
              children: [
                homeScreenHeader(context),
                SizedBox(height: 20.h),
                HomeScreenTabBar(tabController: tabController),
                SizedBox(height: 10.h),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24.r),
                        topRight: Radius.circular(24.r),
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: TabBarView(
                      controller: tabController,
                      children: [
                        FriendsTab(
                          key: ValueKey(_friendsRefreshKey),
                          createNewChallenge: createNewChallenge,
                          onFriendSelected: onFriendSelected,
                          buildViewMoreItem:
                              (context, remainingCount) =>
                                  HomeUtils.buildViewMoreItem(
                                    context,
                                    remainingCount,
                                  ),
                          onViewAllChallenges: () => tabController.animateTo(1),
                          onMarkChallengeCompleted: _markChallengeCompleted,
                        ),
                        ChallengesTab(
                          refreshKey: _challengesRefreshKey,
                          onMarkChallengeCompleted: _markChallengeCompleted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Method to refresh challenges after completion or other changes
  void refreshChallenges() {
    setState(() {
      _challengesRefreshKey++;
    });
  }

  Future<void> _markChallengeCompleted(
    Map<String, dynamic> challenge,
    bool userWon,
  ) async {
    // Close the resolve sheet first so user can see the loading state
    Navigator.of(context).pop();

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    // Show enhanced loading state with branded styling
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.symmetric(vertical: 4.h),
          child: Row(
            children: [
              Container(
                width: 20.w,
                height: 20.w,
                padding: EdgeInsets.all(2.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userWon ? 'Marking as Won...' : 'Marking as Lost...',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Processing challenge completion',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: const Color(0xFFFF5A76),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16.w),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        duration: Duration(seconds: 10), // Long duration, will be replaced
        elevation: 8,
      ),
    );

    try {
      final success = await walletProvider.markChallengeCompleted(
        challengeId: challenge['id'],
        userWon: userWon,
        context: context,
      );

      // Remove loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (success) {
        // Refresh both tabs so challenges list and friends preview update
        setState(() {
          _challengesRefreshKey++;
          _friendsRefreshKey++; // Also refresh friends tab to update challenge previews
        });

        // Show enhanced success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Container(
                    width: 20.w,
                    height: 20.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      userWon
                          ? PhosphorIcons.smileyWink()
                          : PhosphorIcons.smileyMeh(),
                      size: 16.w,
                      color: Colors.green.shade600,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userWon ? 'Challenge Won! 🎉' : 'Challenge Lost',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          userWon
                              ? 'Congratulations on your victory!'
                              : 'Better luck next time!',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            duration: Duration(seconds: 4),
            elevation: 8,
          ),
        );
      } else {
        // Show enhanced error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Row(
                children: [
                  Container(
                    width: 20.w,
                    height: 20.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 16.w,
                      color: Colors.red.shade600,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Challenge Update Failed',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Please try again in a moment',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            duration: Duration(seconds: 4),
            elevation: 8,
          ),
        );
      }
    } catch (e) {
      // Remove loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Show enhanced error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Container(
            padding: EdgeInsets.symmetric(vertical: 4.h),
            child: Row(
              children: [
                Container(
                  width: 20.w,
                  height: 20.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.warning_outlined,
                    size: 16.w,
                    color: Colors.red.shade600,
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connection Error',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.sp,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Check your connection and try again',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16.w),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          duration: Duration(seconds: 4),
          elevation: 8,
        ),
      );
    }
  }

  void onFriendSelected(String name, String walletAddress) async {
    // Determine avatar color based on name
    String avatarColor = HomeUtils.getAvatarColorForFriend(name);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => CreateChallengeScreen(
              friendName: name,
              friendAddress: walletAddress,
              friendAvatarColor: avatarColor,
            ),
      ),
    );

    if (result != null && mounted) {
      // Refresh both tabs so Friends preview and Challenges list update
      setState(() {
        _friendsRefreshKey++;
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
    showAddFriendSheet(
      context,
      onFriendAdded: () {
        // Refresh the friends tab by changing the key
        setState(() {
          _friendsRefreshKey++;
        });
      },
    );
  }
}
