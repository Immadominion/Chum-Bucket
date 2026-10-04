import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/arena/presentation/screens/calls_screen.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/claim_handle_sheet.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_history_screen.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_home.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'dart:async';

import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/add_friend_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/chumbucket_bottom_navigation.dart';
import 'package:chumbucket/shared/screens/home/widgets/escrow_settle.dart';
import 'package:chumbucket/shared/screens/home/widgets/friend_actions.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_hub_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/predictions_home_tab.dart';
import 'package:chumbucket/shared/screens/home/utils/home_utils.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/core/services/app_lifecycle_service.dart';
import 'package:chumbucket/core/services/realtime_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.callReceiptExperienceEnabled = AppConfig.callReceiptExperienceEnabled,
  });

  final bool callReceiptExperienceEnabled;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _friendsRefreshKey = 0; // Key to force FriendsTab refresh
  int _challengesRefreshKey = 0; // Key to force challenges refresh
  DateTime? _lastDataRefresh; // Track when data was last refreshed
  DateTime? _lastBackgroundTime; // Track when app went to background

  @override
  void initState() {
    super.initState();

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize wallet in background (no auto-refresh)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _initializeAuthAndWallet();
      if (mounted) _setupLifecycleCallbacks();
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
    if (mounted) {
      _onLifecycleRefresh();
      _openChallengeHistory();
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
        _refreshSilently();

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

  /// Back from the background: read again what the tabs show, quietly. What
  /// is on screen stays there until the fresh read lands; a failed read keeps
  /// it, with no banner and no "last updated".
  void _refreshSilently() {
    final calls = context.read<CallsProvider?>();
    if (calls != null) {
      unawaited(calls.loadFeed(force: true));
      if (calls.openMarkets.isNotEmpty) {
        unawaited(calls.loadOpenMarkets(force: true));
      }
      if (calls.isSignedIn && calls.following != null) {
        unawaited(calls.loadFollowing(force: true));
      }
    }
    final inbox = context.read<NotificationsProvider?>();
    if (inbox != null && inbox.isSignedIn && inbox.servedAtUtc != null) {
      unawaited(inbox.load(force: true));
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
        if (!mounted) return;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                if (widget.callReceiptExperienceEnabled)
                  CallFeedScreen(
                    onSignInRequested: () => requestCallSignIn(context),
                    onBrowseMarkets: _openCallMarkets,
                    topBanner: const HomeSetupCard(),
                  )
                else
                  PredictionsHomeTab(
                    callReceiptExperienceEnabled:
                        widget.callReceiptExperienceEnabled,
                    onProfileTap: () => _selectDestination(3),
                    onViewCalls: () => _selectDestination(1),
                    onBrowseMarkets: _openCallMarkets,
                    onViewChallenges: _openChallengeHistory,
                    onMarkChallengeCompleted: _markChallengeCompleted,
                  ),
                // Add the preview inside Chumbucket, not in a second shell.
                // Profile, friends, wallet and history retain their routes.
                if (widget.callReceiptExperienceEnabled)
                  const CallMarketsScreen(embedded: true)
                else
                  const CallsScreen(),
                FriendsHubTab(
                  refreshKey: _friendsRefreshKey,
                  onAddFriend: _addFriend,
                  onFriendSelected: onFriendSelected,
                  buildViewMoreItem:
                      (context, remainingCount) =>
                          HomeUtils.buildViewMoreItem(context, remainingCount),
                  onViewAllChallenges: _openChallengeHistory,
                  onMarkChallengeCompleted: _markChallengeCompleted,
                ),
                ProfileScreen(
                  embedded: true,
                  onOpenChallenges: _openChallengeHistory,
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChumbucketBottomNavigation(
              selectedIndex: _selectedIndex,
              onSelected: _selectDestination,
              showMarkets: widget.callReceiptExperienceEnabled,
            ),
          ),
        ],
      ),
    );

    // These tabs use custom headers, not AppBars. Own the system-bar style
    // declaratively so the splash/wallet/detail route cannot leave white
    // icons on our light canvas when this shell becomes visible again.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // An account without a @username is asked, once, to claim one — on
      // onboarding's full-screen step. Onboarding's arrival (Following when it
      // has calls, follows applied, a waiting draft offered again) runs here.
      child:
          widget.callReceiptExperienceEnabled
              ? OnboardingHomeEffects(
                child: UsernameClaimPrompt(
                  present:
                      (context) => presentOnboardingOverlay(
                        context,
                        OnboardingRun.claimOnly,
                      ),
                  child: shell,
                ),
              )
              : shell,
    );
  }

  void _selectDestination(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  void _openCallMarkets() {
    if (widget.callReceiptExperienceEnabled) {
      _selectDestination(1);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(title: const Text('Markets')),
              body: const SafeArea(child: CallMarketsScreen()),
            ),
      ),
    );
  }

  void _openChallengeHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChallengeHistoryScreen(
              refreshKey: _challengesRefreshKey,
              onMarkChallengeCompleted: _markChallengeCompleted,
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

  /// Escrows whose settle is in progress, so a second tap on the same row
  /// cannot open the wallet twice.
  final Set<String> _settlingEscrows = {};

  /// Settles an earlier SOL escrow challenge as its witness (Settings →
  /// History). Creating one is retired; settling one that still holds SOL is
  /// not, because that SOL belongs to the two people in it.
  ///
  /// [initiatorWon] is the witness's verdict: `true` returns the stake to the
  /// challenger, `false` sends it to the witness. The program keeps its fee
  /// (2.5%, at most 0.1 SOL) either way. Only the witness's wallet can sign,
  /// and the escrow account is read first (escrow_settle.dart): the wallet
  /// opens only for a resolve the program can accept.
  Future<void> _markChallengeCompleted(
    Map<String, dynamic> challenge,
    bool initiatorWon,
  ) async {
    if (!mounted) return;
    final walletProvider = context.read<MwaWalletProvider>();
    final witness = context.read<MwaAuthProvider>().walletAddress;
    final stop = escrowSettlePreflight(challenge, connectedWallet: witness);
    if (stop != null || witness == null) {
      SnackBarUtils.showError(
        context,
        title: stop?.title ?? 'Can’t settle this challenge',
        subtitle: stop?.subtitle ?? 'Connect the witness wallet to settle it.',
      );
      return;
    }
    final escrow = escrowAddressOf(challenge);
    if (!_settlingEscrows.add(escrow)) {
      SnackBarUtils.showInfo(
        context,
        title: 'Already settling',
        subtitle: 'Your wallet is already open for this one.',
      );
      return;
    }
    try {
      await _settleEscrow(challenge, initiatorWon, walletProvider, witness);
    } finally {
      _settlingEscrows.remove(escrow);
    }
  }

  Future<void> _settleEscrow(
    Map<String, dynamic> challenge,
    bool initiatorWon,
    MwaWalletProvider walletProvider,
    String witness,
  ) async {
    // Resolve and cancel close the escrow account, and the program checks the
    // resolve against what it stored there: read it before the wallet opens
    // instead of asking the witness to approve a transaction that can only
    // fail.
    SnackBarUtils.showLoading(
      context,
      title: 'Checking the escrow',
      subtitle: 'Reading Solana before your wallet opens.',
    );
    final check = await walletProvider.checkEscrowAccount(
      escrowAddressOf(challenge),
    );
    if (!mounted) return;
    SnackBarUtils.hide(context);
    final decision = planEscrowSettle(
      challenge,
      connectedWallet: witness,
      check: check,
    );
    final EscrowSettlePlan plan;
    switch (decision) {
      case EscrowSettleStop(:final title, :final subtitle, :final settled):
        settled
            ? SnackBarUtils.showInfo(context, title: title, subtitle: subtitle)
            : SnackBarUtils.showError(
              context,
              title: title,
              subtitle: subtitle,
            );
        return;
      case EscrowSettlePlan():
        plan = decision;
    }

    SnackBarUtils.showLoading(
      context,
      title: 'Approve in your wallet',
      subtitle:
          initiatorWon
              ? '${plan.payout} goes back to the challenger.'
              : '${plan.payout} comes to you.',
      duration: const Duration(minutes: 2),
    );
    try {
      final signature = await walletProvider.resolveChallenge(
        challengeAddress: plan.escrow,
        initiatorAddress: plan.initiator,
        initiatorWon: initiatorWon,
        context: context,
      );
      if (!mounted) return;
      SnackBarUtils.hide(context);
      if (signature == null) {
        SnackBarUtils.showError(
          context,
          title: 'Not settled',
          subtitle: 'Your wallet did not send it. Try again.',
        );
        return;
      }

      await ChallengeStateProvider.instance.updateChallenge(challenge['id'], {
        'status': initiatorWon ? 'completed' : 'failed',
        'completedAt': DateTime.now(),
        // The wallet the SOL went to.
        'winnerId': initiatorWon ? plan.initiator : witness,
      });
      if (!mounted) return;
      setState(() {
        _challengesRefreshKey++;
        _friendsRefreshKey++;
      });
      _lastDataRefresh = DateTime.now();
      SnackBarUtils.showSuccess(
        context,
        title: 'Sent to Solana',
        subtitle:
            initiatorWon
                ? 'Once it confirms, ${plan.payout} goes back to the challenger.'
                : 'Once it confirms, ${plan.payout} arrives in your wallet.',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.hide(context);
      SnackBarUtils.showError(
        context,
        title: 'Not settled',
        subtitle: 'Something went wrong before it was sent. Try again.',
      );
      AppLogger.error('Escrow settle failed: $e');
    }
  }

  /// Tapping a friend opens their profile and calls (friend_actions.dart).
  /// It used to open a SOL escrow challenge; that flow is retired.
  void onFriendSelected(Map<String, String> friend) =>
      openFriend(context, friend, onMakeCall: _openCallMarkets);

  void _addFriend() {
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
