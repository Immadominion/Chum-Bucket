/// R "You're on record" (onboarding spec §6, §8): the server's own record of
/// the call just locked — its id, time and stamped price, not the draft —
/// and, only when Chumbucket really sends pushes, the one moment the app
/// asks for notification permission. Otherwise it says where the receipt
/// will show up instead, and asks nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/services/notification_permission_coordinator.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_format.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

enum _Ask { checking, card, decided, none }

class OnRecordScreen extends StatefulWidget {
  const OnRecordScreen({super.key});

  @override
  State<OnRecordScreen> createState() => _OnRecordScreenState();
}

class _OnRecordScreenState extends State<OnRecordScreen> {
  _Ask _ask = _Ask.checking;
  bool _pushLive = false;
  String? _askNote;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final flow = context.read<OnboardingFlowController>();
      final coordinator = flow.notifications;
      final live = await coordinator.isPushLive();
      final ask = live && await coordinator.canAsk();
      if (!mounted) return;
      setState(() {
        _pushLive = live;
        _ask = ask ? _Ask.card : _Ask.none;
      });
      if (ask) {
        flow.app.track(
          OnboardingAnalyticsEvents.notificationPromptShown(
            trigger: 'first_call',
          ),
        );
      }
    });
  }

  Future<void> _notifyMe() async {
    final flow = context.read<OnboardingFlowController>();
    setState(() => _requesting = true);
    final result = await flow.notifications.requestFromPrePrompt();
    if (!mounted) return;
    flow.app.track(
      OnboardingAnalyticsEvents.notificationPermissionResult(
        result: result.wire,
        stage: 'system',
      ),
    );
    setState(() {
      _requesting = false;
      _ask = _Ask.decided;
      _askNote =
          result == NotificationAskResult.granted
              ? null
              : OnboardingCopy.notifyDenied;
    });
  }

  Future<void> _notNow() async {
    final flow = context.read<OnboardingFlowController>();
    await flow.notifications.recordNotNow();
    flow.app.track(
      OnboardingAnalyticsEvents.notificationPermissionResult(
        result: NotificationAskResult.notNow.wire,
        stage: 'pre_prompt',
      ),
    );
    if (mounted) setState(() => _ask = _Ask.decided);
  }

  Future<void> _share(CallFeedEntry entry) async {
    final calls = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      entry: entry,
      surface: AnalyticsSurface.onboarding,
      receipt: CallReceipt.fromEntry(
        entry,
        shareUrl: calls.shareLinkForCall(entry.call.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final entry = flow.lockedEntry;
    if (entry == null) return const SizedBox.shrink();
    final already = flow.alreadyMode;
    final title =
        already
            ? OnboardingCopy.recordTitleAlready
            : OnboardingCopy.recordTitle;
    final reduce = onbReduceMotion(context);
    final cardShown = _ask == _Ask.card;
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 15;

    return OnboardingScaffold(
      announce: title,
      actions:
          cardShown
              ? [
                ChumbucketPrimaryButton(
                  key: const ValueKey('record-notify'),
                  label: OnboardingCopy.notifyCta,
                  busy: _requesting,
                  onPressed: _requesting ? null : _notifyMe,
                ),
                const SizedBox(height: 4),
                OnbTextAction(
                  key: const ValueKey('record-not-now'),
                  label: OnboardingCopy.notifyLater,
                  color: AppColors.textMuted,
                  onPressed: _requesting ? null : _notNow,
                ),
              ]
              : [
                ChumbucketPrimaryButton(
                  key: const ValueKey('record-done'),
                  label: OnboardingCopy.recordDone,
                  onPressed: () => unawaited(flow.finish()),
                ),
                const SizedBox(height: 4),
                OnbTextAction(
                  key: const ValueKey('record-share'),
                  label: OnboardingCopy.recordShare,
                  onPressed: () => unawaited(_share(entry)),
                ),
              ],
      children: [
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Center(
            child: SizedBox.square(
              dimension: 112,
              child:
                  reduce
                      ? const Center(
                        child: BasilIcon(
                          'check-solid',
                          size: 48,
                          color: Color(0xFF07644C),
                        ),
                      )
                      : Lottie.asset(
                        'assets/animations/lottie/success.json',
                        repeat: false,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (_, __, ___) => const BasilIcon(
                              'check-solid',
                              size: 48,
                              color: Color(0xFF07644C),
                            ),
                      ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OnbReveal(
          delay: const Duration(milliseconds: 300),
          rise: 0,
          child: OnbTitle(title, style: OnbText.title),
        ),
        const SizedBox(height: 8),
        OnbReveal(
          delay: const Duration(milliseconds: 300),
          rise: 0,
          child: const OnbBody(OnboardingCopy.recordBodyShort),
        ),
        const SizedBox(height: 20),
        OnbReveal(
          delay: const Duration(milliseconds: 400),
          duration: const Duration(milliseconds: 320),
          rise: 24,
          child: _OwnCallCard(entry: entry),
        ),
        const SizedBox(height: 16),
        if (_ask == _Ask.none && !_pushLive)
          const OnbIconLine(
            key: ValueKey('record-no-push'),
            icon: 'notification-outline',
            text: OnboardingCopy.recordNoPush,
          ),
        if (cardShown)
          OnbReveal(
            delay: const Duration(milliseconds: 900),
            duration: const Duration(milliseconds: 240),
            rise: 16,
            child: OnbSurface(
              key: const ValueKey('record-notify-card'),
              child: Flex(
                direction: largeText ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ChumbucketStateArt(
                    ChumbucketStateArtwork.inbox,
                    size: 72,
                  ),
                  const SizedBox(width: 12, height: 8),
                  Flexible(
                    fit: largeText ? FlexFit.loose : FlexFit.tight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(OnboardingCopy.notifyTitle, style: OnbText.name),
                        const SizedBox(height: 4),
                        Text(OnboardingCopy.notifyBody, style: OnbText.small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_askNote != null)
          Semantics(
            liveRegion: true,
            child: OnbIconLine(icon: 'info-circle-outline', text: _askNote!),
          ),
      ],
    );
  }
}

/// The locked call as the server recorded it.
class _OwnCallCard extends StatelessWidget {
  const _OwnCallCard({required this.entry});
  final CallFeedEntry entry;

  @override
  Widget build(BuildContext context) {
    final call = entry.call;
    final price = OnbFormat.lockedPrice(call);
    final priceLine =
        price == null
            ? OnboardingCopy.recordPriceNotCaptured
            : OnboardingCopy.recordLockedAt(price);
    return OnbSurface(
      key: ValueKey('record-call-${call.id}'),
      child: Semantics(
        label:
            '${OnboardingCopy.recordBody(call.side.wire, entry.market.question, OnbFormat.lockedAt(call))} '
            '$priceLine.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SidePill(side: call.side),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Locked ${OnbFormat.lockedAt(call)}',
                    style: OnbText.meta,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(entry.market.question, style: OnbText.question),
            const SizedBox(height: 10),
            Text(
              priceLine,
              key: const ValueKey('record-price'),
              style: OnbText.small.copyWith(color: AppColors.textPrimary),
            ),
            Text(SharedPriceAttribution.text, style: OnbText.meta),
          ],
        ),
      ),
    );
  }
}

/// "Powered by Panta" under a stamped price.
abstract final class SharedPriceAttribution {
  static const text = 'Powered by Panta · free call, no money involved';
}
