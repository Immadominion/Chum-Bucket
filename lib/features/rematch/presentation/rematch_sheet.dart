/// The rematch sheet.
///
/// Reused verbatim: [ChumbucketWavySheet] / `showChumbucketWavySheet` for the
/// sheet treatment, `AppAvatar` for the opponent, `ChallengeButton` for the
/// primary action, and the `CallsStateView` family for the signed-out and
/// not-available states — so this reads as the same app as the Back/Fade/
/// Challenge sheet rather than a second dialect.
///
/// What is deliberately absent, and must stay absent: an amount field, a stake
/// slider, a balance, a wallet prompt, a countdown, and any "N people are
/// watching" line. A rematch is a dare to go on record, not a wager.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/rematch/data/rematch_offer.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Opens the rematch sheet. Resolves to the challenge that was created, or
/// null if the person backed out.
Future<CallResponseResult?> showRematchSheet({
  required BuildContext context,
  required RematchOffer offer,
}) {
  return showChumbucketWavySheet<CallResponseResult>(
    context: context,
    builder: (_) => RematchSheet(offer: offer),
  );
}

class RematchSheet extends StatefulWidget {
  final RematchOffer offer;

  const RematchSheet({super.key, required this.offer});

  @override
  State<RematchSheet> createState() => _RematchSheetState();
}

class _RematchSheetState extends State<RematchSheet> {
  final TextEditingController _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final provider = context.read<CallsProvider>();
    setState(() => _error = null);
    try {
      final result = await provider.respondToCall(
        widget.offer.toInput(note: _note.text),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on CallsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return ChumbucketWavySheet(
      title: 'Rematch ${offer.opponentDisplayName}',
      subtitle: offer.marketQuestion,
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          if (!provider.isSignedIn) {
            return const SingleChildScrollView(
              child: CallsSignedOutView(
                title: 'Sign in to send a free rematch',
                message:
                    'Sign in to send a rematch. It is free — no wallet, no '
                    'stake, nothing to fund.',
              ),
            );
          }
          if (!offer.isAvailable) {
            return SingleChildScrollView(child: _unavailable(offer));
          }
          return _form(provider, offer);
        },
      ),
    );
  }

  Widget _unavailable(RematchOffer offer) => switch (offer.availability) {
    RematchAvailability.notSettled => const CallsStateView(
      icon: 'clock-outline',
      artwork: ChumbucketStateArtwork.waiting,
      title: 'Not settled yet',
      message:
          'A rematch answers a result. This call is still pending, so there '
          'is nothing to answer yet.',
    ),
    RematchAvailability.ownCall => const CallsStateView(
      icon: 'user-outline',
      artwork: ChumbucketStateArtwork.record,
      title: 'That one is yours',
      message:
          'You can\'t rematch yourself. Open somebody else\'s settled call to '
          'send one.',
    ),
    // Both remaining values are available; kept exhaustive on purpose.
    RematchAvailability.available ||
    RematchAvailability.voidResult => const SizedBox.shrink(),
  };

  Widget _form(CallsProvider provider, RematchOffer offer) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
            children: [
              _Opponent(offer: offer),
              SizedBox(height: 14.h),
              Text(
                offer.resultLine,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.sp,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 14.h),
              const _NothingAtStakeBanner(),
              if (offer.availability == RematchAvailability.voidResult) ...[
                SizedBox(height: 10.h),
                CallsNotice(
                  icon: 'info-circle-outline',
                  color: AppColors.textSecondary,
                  message:
                      'That market was cancelled, so nobody won and nobody '
                      'lost. A rematch here is just a fresh question.',
                ),
              ],
              if (!offer.marketAcceptsNewCalls) ...[
                SizedBox(height: 10.h),
                CallsNotice(
                  icon: 'lock-time-outline',
                  color: AppColors.warning,
                  message:
                      'That market is closed. The invitation still reaches '
                      'them — they pick the market they go on record in.',
                ),
              ],
              SizedBox(height: 14.h),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: kThesisMaxLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kThesisMaxLength),
                ],
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'What are you daring them to call? (optional)',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13.sp,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14.r),
                    borderSide: const BorderSide(
                      color: AppColors.outlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14.r),
                    borderSide: const BorderSide(
                      color: AppColors.outlineVariant,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14.r),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              if (_error != null) ...[
                SizedBox(height: 10.h),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.error, fontSize: 13.sp),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 18.h),
          child: ChallengeButton(
            label: 'Send the rematch',
            blurRadius: false,
            enabled: !provider.isSubmitting,
            isLoading: provider.isSubmitting,
            createNewChallenge: _send,
          ),
        ),
      ],
    );
  }
}

class _Opponent extends StatelessWidget {
  final RematchOffer offer;

  const _Opponent({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          AppAvatar(
            initials: _initials(offer.opponentDisplayName),
            imageUrl: offer.opponentAvatarUrl,
            size: 40,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.opponentDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '@${offer.opponentHandle}',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
          CallOutcomeBadge(outcome: offer.outcome),
        ],
      ),
    );
  }
}

class _NothingAtStakeBanner extends StatelessWidget {
  const _NothingAtStakeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          BasilIcon(
            'info-circle-outline',
            size: 16.w,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'A rematch is an invitation, not a bet. Nothing is escrowed, '
              'nothing is staked, no amount is set and no transaction is '
              'created. No call is made in your name either — they choose '
              'what they call.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}';
  return parts.first.substring(0, 1);
}
