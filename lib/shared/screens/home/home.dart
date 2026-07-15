import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/presentation/screens/matchday_screen.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_details_screen/challenge_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/create_challenge_screens.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/screens/home/widgets/tab_bar.dart';
import 'package:chumbucket/shared/screens/home/utils/home_utils.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/app_lifecycle_service.dart';
import 'package:chumbucket/core/services/realtime_service.dart';
import 'package:chumbucket/core/services/analytics_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController tabController;
  int _friendsRefreshKey = 0; // Key to force FriendsTab refresh
  int _challengesRefreshKey = 0; // Key to force challenges refresh
  bool _isRefreshing = false;
  DateTime? _lastDataRefresh; // Track when data was last refreshed
  DateTime? _lastBackgroundTime; // Track when app went to background

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 3, vsync: this);

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize wallet in background (no auto-refresh)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuthAndWallet();
      _setupLifecycleCallbacks();
    });
  }

  void _setupLifecycleCallbacks() {
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final walletAddress = authProvider.walletAddress;

    // Setup lifecycle service
    AppLifecycleService.instance.initialize(
      userId: walletAddress,
      onShouldRefresh: _onLifecycleRefresh,
    );

    // Setup navigation callback for notification taps
    AppLifecycleService.onNavigateToChallenge = _navigateToChallenge;

    // Setup realtime subscriptions
    if (walletAddress != null) {
      RealtimeService.instance.subscribe(walletAddress);
    }
  }

  void _onLifecycleRefresh() {
    if (mounted) {
      setState(() {
        _friendsRefreshKey++;
        _challengesRefreshKey++;
      });
      _lastDataRefresh = DateTime.now();
      AppLogger.info('HomeScreen: Lifecycle refresh triggered');
    }
  }

  void _navigateToChallenge(String challengeId) {
    // Switch to challenges tab and potentially navigate to detail
    if (mounted) {
      tabController.animateTo(1); // Switch to challenges tab
      // Trigger refresh to ensure we have latest data
      _onLifecycleRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.paused:
        _lastBackgroundTime = DateTime.now();
        break;
      default:
        break;
    }
  }

  void _onAppResumed() {
    // Check if we were in background for more than 10 seconds
    if (_lastBackgroundTime != null) {
      final backgroundDuration = DateTime.now().difference(
        _lastBackgroundTime!,
      );
      if (backgroundDuration.inSeconds > 10) {
        AppLogger.info(
          'App resumed after ${backgroundDuration.inSeconds}s - refreshing',
        );
        _onLifecycleRefresh();

        // Also do a soft database refresh
        final authProvider = Provider.of<MwaAuthProvider>(
          context,
          listen: false,
        );
        final walletAddress = authProvider.walletAddress;
        if (walletAddress != null) {
          ChallengeStateProvider.instance.softRefresh(walletAddress);
        }
      }
    }
  }

  // Initialize authentication and wallet in the background
  Future<void> _initializeAuthAndWallet() async {
    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);

      debugPrint('🏠 HOME: _initializeAuthAndWallet called');
      debugPrint('🏠 HOME: authProvider.state = ${authProvider.state}');
      debugPrint(
        '🏠 HOME: authProvider.walletAddress = ${authProvider.walletAddress}',
      );

      // Make sure auth is initialized
      if (authProvider.state == MwaAuthState.initial) {
        debugPrint('🏠 HOME: Auth state is initial, calling initialize()');
        await authProvider.initialize();
        debugPrint(
          '🏠 HOME: After initialize - walletAddress = ${authProvider.walletAddress}',
        );
      }

      // If authenticated, initialize the wallet
      if (authProvider.isAuthenticated) {
        final walletProvider = Provider.of<MwaWalletProvider>(
          context,
          listen: false,
        );
        debugPrint(
          '🏠 HOME: walletProvider.isInitialized = ${walletProvider.isInitialized}',
        );
        debugPrint(
          '🏠 HOME: walletProvider.walletAddress = ${walletProvider.walletAddress}',
        );

        if (!walletProvider.isInitialized) {
          debugPrint(
            '🏠 HOME: Wallet not initialized, calling initializeFromAuth',
          );
          await walletProvider.initializeFromAuth(authProvider);
          debugPrint(
            '🏠 HOME: After initializeFromAuth - walletAddress = ${walletProvider.walletAddress}',
          );
        }

        // Initialize challenge state (database only, no blockchain sync)
        final walletAddress = authProvider.walletAddress;
        debugPrint(
          '🏠 HOME: About to initialize ChallengeStateProvider with walletAddress: $walletAddress',
        );
        debugPrint(
          '🏠 HOME: ChallengeStateProvider.isInitialized = ${ChallengeStateProvider.instance.isInitialized}',
        );

        if (walletAddress != null) {
          await ChallengeStateProvider.instance.initialize(walletAddress);
          debugPrint(
            '🏠 HOME: After ChallengeState init - ${ChallengeStateProvider.instance.challenges.length} challenges loaded',
          );
        }

        AppLogger.info('Home screen initialization completed');
      }
    } catch (e) {
      AppLogger.error('Error initializing wallet in home screen: $e');
      debugPrint('🏠 HOME: ERROR - $e');
    }
  }

  // Only refresh if data is stale (older than 30 seconds) or forced
  bool _shouldRefreshData({bool forced = false}) {
    if (forced) return true;
    if (_lastDataRefresh == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_lastDataRefresh!);
    return difference.inSeconds > 30;
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
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      final walletProvider = Provider.of<MwaWalletProvider>(
        context,
        listen: false,
      );
      final walletAddress = authProvider.walletAddress;

      if (walletAddress != null) {
        // Ensure wallet is initialized
        String? address = walletProvider.walletAddress;
        if (address == null && !walletProvider.isInitialized) {
          await walletProvider.initializeFromAuth(authProvider);
          address = walletProvider.walletAddress;
        }

        // Force refresh through challenge state provider
        // Use wallet address as userId for MWA
        if (address != null) {
          await ChallengeStateProvider.instance
              .forceRefresh(walletAddress, address)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () {
                  AppLogger.info(
                    'Pull-to-refresh sync timed out - showing local data',
                  );
                },
              );
        } else {
          // Soft refresh if no wallet
          await ChallengeStateProvider.instance.softRefresh(walletAddress);
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
    WidgetsBinding.instance.removeObserver(this);
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
                      // Arena - solo staking into a shared match-outcome pot
                      // (chumbucket_arena program). This is separate from
                      // friend challenges and signs through MWA.
                      const MatchdayScreen(),
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
    if (!mounted) return;

    final walletProvider = Provider.of<MwaWalletProvider>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final walletAddress = authProvider.walletAddress;

    // Debug: Log challenge data to understand what we have
    debugPrint('🔍 DEBUG: Challenge data for resolution:');
    debugPrint('🔍 DEBUG: id=${challenge['id']}');
    debugPrint('🔍 DEBUG: escrowAddress=${challenge['escrowAddress']}');
    debugPrint('🔍 DEBUG: escrow_address=${challenge['escrow_address']}');
    debugPrint('🔍 DEBUG: multisig_address=${challenge['multisig_address']}');
    debugPrint('🔍 DEBUG: All keys: ${challenge.keys.toList()}');

    // Show enhanced loading state with branded styling
    SnackBarUtils.showChallengeLoading(context, isWinning: userWon);

    try {
      // Use resolveChallenge from MwaWalletProvider
      // The initiatorAddress is the one who created the challenge
      // Handle different key names from different sources
      final escrowAddr =
          challenge['escrowAddress'] ??
          challenge['escrow_address'] ??
          challenge['multisig_address'];

      debugPrint('🔍 DEBUG: Final escrowAddr=$escrowAddr');

      if (escrowAddr == null || escrowAddr.toString().isEmpty) {
        throw Exception(
          'Challenge has no escrow address - cannot resolve on-chain. Debug: escrowAddress=${challenge['escrowAddress']}, keys=${challenge.keys.toList()}',
        );
      }

      final txSignature = await walletProvider.resolveChallenge(
        challengeAddress: escrowAddr,
        initiatorAddress:
            challenge['initiator_address'] ??
            challenge['member1_address'] ??
            challenge['creator_wallet_address'] ??
            '',
        initiatorWon: userWon,
        context: context,
      );

      final success = txSignature != null;

      // Remove loading snackbar
      if (mounted) {
        SnackBarUtils.hide(context);
      }

      // NOTE: Don't pop here - the resolve sheet already pops itself in _safeMarkCompleted

      if (success) {
        // Update challenge state provider and persist to database
        // Use walletAddress instead of currentUser.id for MWA
        // Status is 'completed' if user won, 'failed' if they lost
        await ChallengeStateProvider.instance.updateChallenge(challenge['id'], {
          'status': userWon ? 'completed' : 'failed',
          'completedAt': DateTime.now(),
          'winnerId': userWon ? walletAddress : null,
        });

        // Track resolution analytics (YOUR FEE MONEY!) - fire-and-forget
        final winnerAmount =
            (challenge['winner_amount_sol'] ?? challenge['winner_amount'] ?? 0)
                .toDouble();
        final feeSol =
            (challenge['platform_fee_sol'] ?? challenge['platform_fee'] ?? 0)
                .toDouble();
        AnalyticsService.trackChallengeResolved(
          challengeId: challenge['id'],
          winnerWallet:
              userWon
                  ? walletAddress
                  : (challenge['member1_address'] ??
                      challenge['creator_wallet_address'] ??
                      ''),
          winnerName: userWon ? null : challenge['friendName'],
          initiatorWon: userWon,
          winnerAmountSol: winnerAmount,
          feeSol: feeSol,
        ).catchError((e) => debugPrint('Analytics tracking failed: $e'));

        // Send push notification to initiator about result (fire-and-forget)
        final initiatorWallet =
            challenge['member1_address'] ?? challenge['creator_wallet_address'];
        if (initiatorWallet != null) {
          FcmTokenService.notifyChallengeResolved(
            challengeId: challenge['id'],
            initiatorWallet: initiatorWallet,
            initiatorWon: userWon,
            winnerAmountSol:
                challenge['winner_amount_sol'] ?? challenge['winner_amount'],
          ).catchError((e) => debugPrint('Notification failed: $e'));
        }

        // Force refresh both tabs since challenge status changed
        if (mounted) {
          setState(() {
            _challengesRefreshKey++;
            _friendsRefreshKey++;
          });
          _lastDataRefresh = DateTime.now();
        }

        // Show enhanced success message
        if (mounted) {
          SnackBarUtils.showChallengeSuccess(context, userWon: userWon);
        }
      } else {
        // Show enhanced error message
        if (mounted) {
          SnackBarUtils.showChallengeError(context);
        }
      }
    } catch (e) {
      // Remove loading snackbar
      if (mounted) {
        SnackBarUtils.hide(context);
      }

      // Show enhanced error message
      if (mounted) {
        SnackBarUtils.showChallengeError(context, errorMessage: e.toString());
      }
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
