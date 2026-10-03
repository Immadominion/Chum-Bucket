import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/core/navigation/deep_link_host.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/presentation/screens/mwa_login_screen.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_flow.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_home.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';

/// The session as the entry table sees it.
EntrySessionState entrySessionStateOf(ChumbucketSession? session) {
  if (session == null) return EntrySessionState.none;
  if (session.isReady) return EntrySessionState.ready;
  if (session.needsUsername) return EntrySessionState.needsAccount;
  if (!session.hasSupabaseSession) return EntrySessionState.none;
  final error = session.error;
  if (session.isBusy || (error != null && error.isNetwork)) {
    return EntrySessionState.unconfirmed;
  }
  if (session.status == SessionStatus.failed) return EntrySessionState.refused;
  return EntrySessionState.unconfirmed;
}

/// The first screen: the brand on the same #F4F4F4 as the native launch
/// window (no flash, no purple), for as short as routing allows, then the
/// one destination the entry table picks (onboarding spec §3, §6 S0).
///
/// * Never an OS permission dialog here.
/// * At least 700ms (brand recognition), at most 2.5s waiting on the server;
///   a Block Store restore may hold it up to 6s, saying so after 800ms.
/// * A shared link opened the app: Home under it, never Welcome in front.
class MwaSplashScreen extends StatefulWidget {
  const MwaSplashScreen({
    super.key,
    this.peopleFirst = AppConfig.callReceiptExperienceEnabled,
    this.deepLinkPending,
    this.minimumDuration = const Duration(milliseconds: 700),
    this.whoamiCap = const Duration(milliseconds: 2500),
    this.restoreCap = const Duration(seconds: 6),
    this.homeBuilder,
    this.clock,
  });

  final bool peopleFirst;

  /// Whether the launch link is one the app opens. Default: [ColdStartLink].
  final Future<bool> Function()? deepLinkPending;
  final Duration minimumDuration;
  final Duration whoamiCap;
  final Duration restoreCap;

  /// Test seam for Home.
  final WidgetBuilder? homeBuilder;
  final DateTime Function()? clock;

  @override
  State<MwaSplashScreen> createState() => _MwaSplashScreenState();
}

class _MwaSplashScreenState extends State<MwaSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  Timer? _restoringLabelTimer;
  Timer? _minimumTimer;
  bool _showRestoring = false;
  bool _routed = false;
  SessionContinuity? _continuity;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (onbReduceMotion(context)) {
        _motion.value = 1;
      } else {
        _motion.forward();
      }
      unawaited(_route());
    });
  }

  @override
  void dispose() {
    _continuity?.restoring.removeListener(_onRestoring);
    _restoringLabelTimer?.cancel();
    _minimumTimer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  void _onRestoring() {
    final restoring = _continuity?.restoring.value ?? false;
    if (restoring) {
      _restoringLabelTimer ??= Timer(const Duration(milliseconds: 800), () {
        if (mounted && (_continuity?.restoring.value ?? false)) {
          setState(() => _showRestoring = true);
        }
      });
    } else {
      _restoringLabelTimer?.cancel();
      _restoringLabelTimer = null;
      if (_showRestoring && mounted) setState(() => _showRestoring = false);
    }
  }

  Widget _home(BuildContext context) =>
      widget.homeBuilder?.call(context) ?? const HomeScreen();

  /// Replaces this splash — and only it — with [route], so a shared link
  /// already pushed on top stays where it is.
  void _replaceWith(Route<void> route) {
    if (!mounted || _routed) return;
    _routed = true;
    final self = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (self != null && self.isActive) {
      navigator.replace(oldRoute: self, newRoute: route);
    } else {
      navigator.pushReplacement(route);
    }
  }

  Route<void> _fade(WidgetBuilder builder) =>
      FadeThroughRoute<void>(builder: builder);

  Route<void> _flow(
    OnboardingRun run, {
    OnboardingStep? resumeAt,
    bool sessionEnded = false,
  }) => _fade(
    (_) => OnboardingFlow(
      run: run,
      resumeAt: resumeAt,
      sessionEnded: sessionEnded,
      onExit: (context, exit) => exitToHome(context, exit, _home),
    ),
  );

  Future<void> _route() async {
    final started = _now;
    final onboarding = context.read<OnboardingController?>();
    final auth = context.read<MwaAuthProvider?>();
    final session = context.read<ChumbucketSession?>();
    final continuity = context.read<SessionContinuity?>();
    final linkProbe =
        widget.deepLinkPending ??
        () => ColdStartLink.ownedLinkPending.timeout(
          const Duration(milliseconds: 600),
          onTimeout: () => false,
        );

    await Future.wait(<Future<void>>[
      if (onboarding != null && !onboarding.loaded) onboarding.load(),
      if (auth != null && auth.state == MwaAuthState.initial) auth.initialize(),
    ]);
    if (!mounted) return;

    if (!widget.peopleFirst) {
      await _holdMinimum(started);
      if (mounted) await _legacyRoute(auth);
      return;
    }

    final deepLink = await linkProbe();
    if (!mounted) return;

    // A session backed up to Block Store comes back after a reinstall (B2).
    var restoreFailed = false;
    if (continuity != null && session?.hasSupabaseSession != true) {
      _continuity = continuity..restoring.addListener(_onRestoring);
      _onRestoring();
      final restored = await continuity.restoreOnLaunch().timeout(
        widget.restoreCap,
        onTimeout: () => false,
      );
      if (!mounted) return;
      final result =
          continuity.settled
              ? continuity.lastRestore ?? SessionRestoreResult.none
              : SessionRestoreResult.unreachable;
      if (result != SessionRestoreResult.none) {
        AnalyticsRecorder.instance.record(
          OnboardingAnalyticsEvents.sessionRestore(result: result.wire),
        );
      }
      restoreFailed =
          !restored &&
          (result == SessionRestoreResult.failed ||
              result == SessionRestoreResult.unreachable);
      if (restored) {
        // The SDK announces the adopted session; wait for the account to
        // pick it up.
        await _waitFor(
          session,
          () => session?.hasSupabaseSession == true,
          widget.whoamiCap,
        );
      }
    }

    // A stored session waits for the server's answer, briefly (row 6).
    if (session != null &&
        session.hasSupabaseSession &&
        !session.isReady &&
        !session.needsUsername) {
      await _waitFor(session, () => !session.isBusy, widget.whoamiCap);
    }
    if (!mounted) return;
    await session?.loadLastSignInMethod();
    if (!mounted) return;

    final record = onboarding?.record;
    final entry = decideEntry(
      EntryInputs(
        peopleFirst: true,
        deepLinkPending: deepLink,
        session: entrySessionStateOf(session),
        needsHandleClaim: session?.needsHandleClaim ?? false,
        handleClaimDeferred: record?.handleClaimDeferred ?? false,
        status: record?.status ?? OnboardingStatus.fresh,
        stageUpdatedAt: record?.stageAtUtc,
        restoreFailed: restoreFailed,
        legacyWalletSignedIn: auth?.isAuthenticated ?? false,
        upgradeIntroSeen: record?.upgradeIntroSeen ?? false,
        signedInHereBefore: session?.lastSignInMethod != null,
        now: _now,
      ),
    );
    AppLogger.info('Splash: entry ${entry.name}');
    await _holdMinimum(started);
    if (!mounted) return;
    if (auth?.isAuthenticated == true) _triggerInitialSync(auth!);

    switch (entry) {
      case OnboardingEntry.legacy:
        await _legacyRoute(auth);
      case OnboardingEntry.deepLink:
        await onboarding?.defer();
        _replaceWith(_fade(_home));
      case OnboardingEntry.homeThenClaim:
      case OnboardingEntry.home:
      case OnboardingEntry.homeReconnecting:
      case OnboardingEntry.homeSignedOut:
      case OnboardingEntry.restoring:
        _replaceWith(_fade(_home));
      case OnboardingEntry.resume:
        final stage = OnboardingStep.values.where(
          (s) => s.wire == record?.stage,
        );
        _replaceWith(
          _flow(
            OnboardingRun.newUser,
            resumeAt: stage.isEmpty ? null : stage.first,
          ),
        );
      case OnboardingEntry.claimUsername:
        _replaceWith(_flow(OnboardingRun.claimOnly));
      case OnboardingEntry.upgrade:
        _replaceWith(_flow(OnboardingRun.upgrade));
      case OnboardingEntry.welcomeBack:
        _replaceWith(
          _flow(OnboardingRun.welcomeBack, sessionEnded: restoreFailed),
        );
      case OnboardingEntry.welcome:
        _replaceWith(_flow(OnboardingRun.newUser));
    }
  }

  /// The brand stays at least [MwaSplashScreen.minimumDuration]. A timer the
  /// splash owns, so nothing fires after it is gone.
  Future<void> _holdMinimum(DateTime started) {
    final left = widget.minimumDuration - _now.difference(started);
    if (left <= Duration.zero || !mounted) return Future<void>.value();
    final done = Completer<void>();
    _minimumTimer?.cancel();
    _minimumTimer = Timer(left, done.complete);
    return done.future;
  }

  /// Resolves when [done] holds or [cap] passes, listening to [session].
  Future<void> _waitFor(
    ChumbucketSession? session,
    bool Function() done,
    Duration cap,
  ) async {
    if (session == null || done()) return;
    final completer = Completer<void>();
    void check() {
      if (!completer.isCompleted && done()) completer.complete();
    }

    session.addListener(check);
    final timer = Timer(cap, () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await completer.future;
    } finally {
      timer.cancel();
      session.removeListener(check);
    }
  }

  /// The challenge build (`CALL_RECEIPT_EXPERIENCE` off): its original
  /// wallet-only door and name gate, unchanged.
  Future<void> _legacyRoute(MwaAuthProvider? auth) async {
    if (auth == null || !auth.isAuthenticated) {
      _replaceWith(_fade((_) => const MwaLoginScreen()));
      return;
    }
    final profile = await context.read<ProfileProvider>().fetchUserProfile(
      auth.walletAddress!,
    );
    if (!mounted) return;
    final hasName =
        profile != null &&
        profile['full_name'] != null &&
        profile['full_name'].toString().trim().isNotEmpty;
    final hasDomain = auth.snsDomain != null && auth.snsDomain!.isNotEmpty;
    if (!hasName && !hasDomain) {
      _replaceWith(
        _fade(
          (_) =>
              const EditProfileScreen(showCancelIcon: false, isRequired: true),
        ),
      );
      return;
    }
    _replaceWith(_fade(_home));
    _triggerInitialSync(auth);
  }

  /// Loads a wallet user's challenges after Home is up (legacy surfaces).
  void _triggerInitialSync(MwaAuthProvider auth) {
    final walletAddress = auth.walletAddress;
    if (walletAddress == null) return;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () async {
        try {
          await EfficientSyncService.instance.getChallenges(
            userId: walletAddress,
            walletAddress: walletAddress,
          );
        } catch (e) {
          AppLogger.error('Delayed sync failed: $e');
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = CurvedAnimation(
      parent: _motion,
      curve: const Interval(200 / 560, 480 / 560, curve: Curves.easeOutCubic),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Semantics(
          label: 'Chumbucket',
          container: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The bucket sits exactly where the native launch window drew
              // it (centred, 121dp), so the hand-off shows no jump or flash.
              const Center(child: ExcludeSemantics(child: SplashBucket())),
              Center(
                child: Transform.translate(
                  offset: const Offset(
                    0,
                    SplashBucket.height / 2 + 20 + SplashWordmark.height / 2,
                  ),
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: word,
                      builder:
                          (context, child) => Opacity(
                            opacity: word.value.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, 12 * (1 - word.value)),
                              child: child,
                            ),
                          ),
                      child: const SplashWordmark(),
                    ),
                  ),
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: const Offset(
                    0,
                    SplashBucket.height / 2 + 20 + SplashWordmark.height + 36,
                  ),
                  child: AnimatedOpacity(
                    opacity: _showRestoring ? 1 : 0,
                    duration:
                        onbReduceMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _showRestoring ? OnboardingCopy.splashRestoring : '',
                        key: const ValueKey('splash-restoring'),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bucket from `bucket_logo.png`, cropped to its drawing (the PNG has
/// wide transparent margins) at the size the native launch window shows the
/// launcher foreground: 121dp wide.
class SplashBucket extends StatelessWidget {
  const SplashBucket({super.key});

  static const double width = 121;
  static const double height = 114;

  // The drawing's box inside the 1024x1536 source, measured from its alpha.
  static const double _scale = width / 706;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: 1024 * _scale,
        maxHeight: 1536 * _scale,
        child: Transform.translate(
          offset: const Offset(-200 * _scale, -320 * _scale),
          child: Image.asset(
            'assets/images/ai_gen/logo/bucket_logo.png',
            width: 1024 * _scale,
            height: 1536 * _scale,
            fit: BoxFit.fill,
            cacheWidth: 600,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

/// "The Chum Bucket" lettering, cropped to its drawing, 180dp wide.
class SplashWordmark extends StatelessWidget {
  const SplashWordmark({super.key});

  static const double width = 180;
  static const double _scale = width / 862;
  static const double height = 526 * _scale;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: 1024 * _scale,
        maxHeight: 1024 * _scale,
        child: Transform.translate(
          offset: const Offset(-88 * _scale, -240 * _scale),
          child: Image.asset(
            'assets/images/ai_gen/logo/chum_text.png',
            width: 1024 * _scale,
            height: 1024 * _scale,
            fit: BoxFit.fill,
            cacheWidth: 640,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}
