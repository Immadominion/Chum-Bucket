/// Onboarding's footprint on Home (onboarding spec §6 "Home arrival", §7 K1):
///
/// * the first Home after a run opens on Following only when the person
///   followed someone with a call to show, refreshes the feed after a call,
///   and says what happened to the follows chosen during the run;
/// * a later sign-in (from any sheet) applies follows still waiting on this
///   phone and offers the waiting draft call again — never locks it;
/// * "Make Home yours" for people who skipped setting Home up.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_flow.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

/// A run pushed over Home (the setup card, "Pick your @username"); it closes
/// itself when done.
Route<void> onboardingOverlayRoute(OnboardingRun run) =>
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder:
          (_) => OnboardingFlow(
            run: run,
            onExit: (context, _) => Navigator.of(context).maybePop(),
          ),
    );

/// Wraps Home's shell.
class OnboardingHomeEffects extends StatefulWidget {
  const OnboardingHomeEffects({super.key, required this.child});
  final Widget child;

  @override
  State<OnboardingHomeEffects> createState() => _OnboardingHomeEffectsState();
}

class _OnboardingHomeEffectsState extends State<OnboardingHomeEffects> {
  ChumbucketSession? _session;
  bool _wasReady = false;
  bool _offeredDraft = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_arrive());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<ChumbucketSession?>();
    if (identical(session, _session)) return;
    _session?.removeListener(_onSession);
    _session = session?..addListener(_onSession);
    _wasReady = session?.isReady ?? false;
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    super.dispose();
  }

  OnboardingController? get _app => context.read<OnboardingController?>();

  Future<void> _arrive() async {
    final app = _app;
    if (app == null) return;
    await app.load();
    if (!mounted) return;
    final calls = context.read<CallsProvider>();
    final arrival = app.takeArrival();
    if (arrival != null) {
      if (arrival.madeCall) unawaited(calls.loadFeed(force: true));
      if (arrival.followed > 0 && calls.isSignedIn) {
        try {
          final page = await calls.repository.fetchFeed(
            mode: CallFeedMode.following,
            viewerUserId: calls.viewerUserId,
            limit: 1,
          );
          if (!mounted) return;
          final mode = homeArrivalMode(
            followed: arrival.followed,
            followingFeedEntries: page.entries.length,
          );
          if (mode != calls.feedMode) unawaited(calls.setFeedMode(mode));
        } catch (_) {
          // Global stays: never an empty "Following" on the first visit.
        }
      }
      if (!mounted) return;
      _sayFollows(arrival.followed, arrival.failed, null);
    }
    // Signed in already, with something still waiting from before.
    if (_session?.isReady == true) await _afterSignIn();
  }

  void _onSession() {
    final ready = _session?.isReady ?? false;
    if (ready && !_wasReady) unawaited(_afterSignIn());
    _wasReady = ready;
  }

  Future<void> _afterSignIn() async {
    final app = _app;
    if (app == null || !mounted) return;
    await app.load();
    if (!mounted) return;
    final calls = context.read<CallsProvider>();
    // The viewer is bound to the provider when the session's dependants
    // rebuild; let that frame happen first.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !calls.isSignedIn) return;
    if (app.pendingFollowIds.isNotEmpty) {
      final result = await app.applyPendingFollows(calls);
      if (!mounted || result == null) return;
      _sayFollows(result.succeeded.length, result.failed.length, null);
    }
    final draft = app.pendingCall;
    if (draft != null && !_offeredDraft) {
      _offeredDraft = true;
      _offerDraft(draft);
    }
  }

  void _sayFollows(int followed, int failed, String? name) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    if (followed > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(OnboardingCopy.followingApplied(followed, name)),
        ),
      );
    }
    if (failed > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(OnboardingCopy.followApplyFailed(failed))),
      );
    }
  }

  void _offerDraft(PendingCall draft) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('home-pending-call'),
        duration: const Duration(seconds: 10),
        content: Text(
          OnboardingCopy.pendingCallBody(
            draft.side.wire,
            draft.question ?? 'your market',
          ),
        ),
        action: SnackBarAction(
          label: OnboardingCopy.pendingCallCta,
          onPressed: () => unawaited(_resumeDraft(draft)),
        ),
      ),
    );
  }

  /// Reopens the draft for a fresh Lock, checked against the server first.
  Future<void> _resumeDraft(PendingCall draft) async {
    final app = _app;
    if (app == null) return;
    final calls = context.read<CallsProvider>();
    final detail = await calls.loadMarketDetail(draft.marketId, force: true);
    if (!mounted) return;
    final own = detail?.viewerCall;
    if (own != null ||
        detail == null ||
        !isCallReadyMarket(detail.market, DateTime.now())) {
      await app.clearDraft();
      if (own != null && mounted) _openCall(own.call.id);
      return;
    }
    final handle = _session?.handle;
    CallFeedEntry? locked;
    if (draft.kind == PendingCallKind.call) {
      locked = await showCallComposer(
        context: context,
        market: detail.market,
        sharePrice: detail.sharePrice,
        snapshot: detail.snapshot,
        surface: AnalyticsSurface.onboarding,
        note: OnboardingCopy.callSignedInNote(handle),
        initialDraft: CallComposerDraft(
          marketId: draft.marketId,
          side: draft.side,
          thesis: draft.thesis,
          visibility: draft.visibility,
          confidence: draft.confidence,
        ),
        refreshPrice:
            () async =>
                (await calls.loadMarketDetail(
                  draft.marketId,
                  force: true,
                ))?.sharePrice,
      );
    } else {
      final target = await calls.loadCall(
        draft.targetCallId!,
        reportOpen: false,
      );
      if (!mounted || target == null) {
        await app.clearDraft();
        return;
      }
      final result = await showCallResponseSheet(
        context: context,
        entry: target.entry,
        initialKind:
            draft.kind == PendingCallKind.fade
                ? CallResponseKind.fade
                : CallResponseKind.back,
        surface: AnalyticsSurface.onboarding,
        note: OnboardingCopy.callSignedInNote(handle),
      );
      locked = result?.resultingCall;
    }
    if (locked == null || !mounted) return;
    await app.clearDraft();
    if (mounted) _openCall(locked.call.id);
  }

  void _openCall(String callId) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CallDetailScreen(callId: callId)),
  );

  @override
  Widget build(BuildContext context) => widget.child;
}

/// K1 "Make Home yours": at the top of Home for people who skipped setting
/// it up. At most three sessions; gone after "Not now" twice or once set up.
class HomeSetupCard extends StatefulWidget {
  const HomeSetupCard({super.key});

  @override
  State<HomeSetupCard> createState() => _HomeSetupCardState();
}

class _HomeSetupCardState extends State<HomeSetupCard> {
  bool _counted = false;
  bool _closing = false;

  Future<void> _setUp() async {
    final app = context.read<OnboardingController>();
    await Navigator.of(
      context,
    ).push(onboardingOverlayRoute(OnboardingRun.homeSetup));
    if (!mounted) return;
    // Topics or follows may have changed what Home and Markets show.
    final calls = context.read<CallsProvider>();
    unawaited(calls.loadTopCalls(force: true));
    final arrival = app.takeArrival();
    if (arrival != null && arrival.followed > 0) {
      unawaited(calls.loadFeed(force: true));
    }
  }

  void _later() {
    if (onbReduceMotion(context)) {
      unawaited(context.read<OnboardingController>().declineHomeCard());
      return;
    }
    setState(() => _closing = true);
  }

  void _closed() {
    if (_closing && mounted) {
      unawaited(context.read<OnboardingController>().declineHomeCard());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<OnboardingController?>();
    if (app == null || !app.homeCardEligible) return const SizedBox.shrink();
    if (!_counted) {
      _counted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(app.noteHomeCardShown());
      });
    }
    final reduce = onbReduceMotion(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      child: AnimatedOpacity(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeIn,
        opacity: _closing ? 0 : 1,
        onEnd: _closed,
        child:
            _closing
                ? const SizedBox(width: double.infinity)
                : OnbSurface(
                  key: const ValueKey('home-setup-card'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ChumbucketStateArt(
                            ChumbucketStateArtwork.people,
                            size: 64,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    OnboardingCopy.cardTitle,
                                    style: OnbText.section,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  OnboardingCopy.cardBody,
                                  style: OnbText.small,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            key: const ValueKey('home-setup-later'),
                            onPressed: _later,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: AppColors.textMuted,
                            ),
                            child: Text(
                              OnboardingCopy.cardLater,
                              style: OnbText.chip.copyWith(
                                fontSize: 14,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          _CompactPrimary(
                            key: const ValueKey('home-setup-cta'),
                            label: OnboardingCopy.cardCta,
                            onPressed: _setUp,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}

/// The primary action's gradient at chip size, for a card's own action.
class _CompactPrimary extends StatelessWidget {
  const _CompactPrimary({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: ChumbucketPrimaryButton.gradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: OnbText.name.copyWith(
                    fontSize: 15,
                    color: AppColors.surface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Where a finished first run lands: Home, replacing everything.
void exitToHome(BuildContext context, FlowExit exit, WidgetBuilder home) {
  if (exit == FlowExit.pop) {
    Navigator.of(context).maybePop();
    return;
  }
  Navigator.of(context).pushAndRemoveUntil(
    FadeThroughRoute<void>(
      builder: home,
      duration: const Duration(milliseconds: 300),
    ),
    (_) => false,
  );
}
