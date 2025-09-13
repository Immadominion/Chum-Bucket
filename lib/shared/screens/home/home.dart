import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_details_screen/challenge_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

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
  DateTime? _lastDataRefresh; // Track when data was last refreshed

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);

    // Initialize wallet and load local challenges immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuthAndWallet();
      // Initial load without forcing refresh indicators
      _loadInitialData();
    });
  }

  // Load initial data without forcing refresh indicators
  Future<void> _loadInitialData() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser != null) {
        AppLogger.info('Loading initial data for home screen');

        // Trigger initial data load for both tabs
        if (mounted) {
          setState(() {
            _challengesRefreshKey++;
            _friendsRefreshKey++;
          });
          _lastDataRefresh = DateTime.now();
        }

        AppLogger.info('Initial data load completed');
      }
    } catch (e) {
      AppLogger.error('Error loading initial data: $e');
    }
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

        // After wallet is ready, try blockchain sync in background (don't block UI)
        _tryBackgroundSync(authProvider, walletProvider);
      }
    } catch (e) {
      AppLogger.error('Error initializing wallet in home screen: $e');
      // Don't show errors to users here as this is background initialization
    }
  }

  // Try blockchain sync in background without blocking UI
  Future<void> _tryBackgroundSync(
    AuthProvider authProvider,
    WalletProvider walletProvider,
  ) async {
    try {
      final currentUser = authProvider.currentUser;
      final walletAddress = walletProvider.walletAddress;

      if (currentUser != null && walletAddress != null) {
        AppLogger.info('Attempting background blockchain sync');

        // Try blockchain sync with timeout to prevent hanging
        await EfficientSyncService.instance
            .forceBlockchainSync(
              userId: currentUser.id,
              walletAddress: walletAddress,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                AppLogger.info(
                  'Background sync timed out - continuing with local data',
                );
              },
            );

        // Only refresh UI if data should be refreshed
        if (mounted && _shouldRefreshData()) {
          setState(() {
            _challengesRefreshKey++;
            _friendsRefreshKey++;
          });
          _lastDataRefresh = DateTime.now();
        }
      }
    } catch (e) {
      AppLogger.error('Background sync failed (non-blocking): $e');
      // Don't show errors to users - app works fine with local data
    }
  }

  // Only refresh if data is stale (older than 30 seconds) or forced
  bool _shouldRefreshData({bool forced = false}) {
    if (forced) return true;
    if (_lastDataRefresh == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_lastDataRefresh!);
    return difference.inSeconds >
        30; // Refresh if data is older than 30 seconds
  }

  Future<void> _onPullToRefresh() async {
    if (_isRefreshing) return;

    // Always refresh when user explicitly pulls to refresh
    setState(() {
      _isRefreshing = true;
      _friendsRefreshKey++;
      _challengesRefreshKey++;
    });

    _lastDataRefresh = DateTime.now();

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final currentUser = authProvider.currentUser;

      if (currentUser != null) {
        // First, refresh local challenges immediately
        await EfficientSyncService.instance.getChallenges(
          userId: currentUser.id,
          walletAddress: null, // Local database doesn't need wallet
        );

        // Then try blockchain sync with timeout
        String? address = walletProvider.walletAddress;
        if (address == null && !walletProvider.isInitialized) {
          await walletProvider.initializeWallet(context);
          address = walletProvider.walletAddress;
        }

        if (address != null) {
          await EfficientSyncService.instance
              .forceBlockchainSync(
                userId: currentUser.id,
                walletAddress: address,
              )
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  AppLogger.info(
                    'Pull-to-refresh sync timed out - showing local data',
                  );
                },
              );
        }
      }
    } catch (e) {
      AppLogger.error('Home pull-to-refresh error: $e');
      // Show user-friendly message only for pull-to-refresh failures
      if (mounted) {
        SnackBarUtils.showSyncError(context);
      }
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
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _onPullToRefresh,
        color: Theme.of(context).primaryColor,
        notificationPredicate: (_) => true, // Listen to nested scrollables
        child: Padding(
          padding: EdgeInsets.only(left: 16.w, right: 16.w, top: 60.h),
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
    );
  }

  // Method to refresh challenges after completion or other changes
  void refreshChallenges({bool forced = false}) {
    if (_shouldRefreshData(forced: forced)) {
      setState(() {
        _challengesRefreshKey++;
      });
      _lastDataRefresh = DateTime.now();
    }
  }

  Future<void> _markChallengeCompleted(
    Map<String, dynamic> challenge,
    bool userWon,
  ) async {
    // Close the resolve sheet first so user can see the loading state
    Navigator.of(context).pop();

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    // Show enhanced loading state with branded styling
    SnackBarUtils.showChallengeLoading(context, isWinning: userWon);

    try {
      final success = await walletProvider.markChallengeCompleted(
        challengeId: challenge['id'],
        userWon: userWon,
        context: context,
      );

      // Remove loading snackbar
      SnackBarUtils.hide(context);

      if (success) {
        // Force refresh both tabs since challenge status changed
        setState(() {
          _challengesRefreshKey++;
          _friendsRefreshKey++;
        });
        _lastDataRefresh = DateTime.now();

        // Show enhanced success message
        SnackBarUtils.showChallengeSuccess(context, userWon: userWon);
      } else {
        // Show enhanced error message
        SnackBarUtils.showChallengeError(context);
      }
    } catch (e) {
      // Remove loading snackbar
      SnackBarUtils.hide(context);

      // Show enhanced error message
      SnackBarUtils.showChallengeError(context, errorMessage: e.toString());
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
      // Force refresh both tabs since new challenge was created
      setState(() {
        _friendsRefreshKey++;
        _challengesRefreshKey++;
      });
      _lastDataRefresh = DateTime.now();

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
        // Force refresh friends tab since new friend was added
        setState(() {
          _friendsRefreshKey++;
        });
        _lastDataRefresh = DateTime.now();
      },
    );
  }
}
