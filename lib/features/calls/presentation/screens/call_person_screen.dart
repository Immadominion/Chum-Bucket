/// A person's calls, keyed by the canonical `public.users.id` (or handle).
///
/// This is deliberately **not** `CallerProfileScreen`: that screen is keyed by
/// a wallet address (`caller_profile_screen.dart:15`) and this slice must work
/// with no wallet at all. When a person happens to have a wallet linked, the
/// arena profile is offered as a secondary link rather than made the identity.
///
/// The header is accuracy-first, never PnL-first: a call has no money in it, so
/// there is no P&L to lead with — and accuracy itself is only ever rendered as
/// a percentage once there is enough settled history for a percentage to mean
/// something. See `lib/features/record/data/category_record.dart`.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/presentation/screens/caller_profile_screen.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:chumbucket/features/record/data/category_record.dart';
import 'package:chumbucket/features/record/presentation/widgets/category_record_card.dart';
import 'package:chumbucket/features/rematch/data/rematch_offer.dart';
import 'package:chumbucket/features/rematch/presentation/rematch_sheet.dart';
import 'package:chumbucket/features/rematch/presentation/widgets/rematch_button.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

class CallPersonScreen extends StatefulWidget {
  /// A `public.users.id`, a handle, or `@handle`.
  final String personRef;
  final String? sharedByHandle;
  final VoidCallback? onSignInRequested;

  /// Lets the arena hand-off be switched off where `ArenaProvider` is not in
  /// the tree (tests, embedded previews).
  final bool allowArenaProfileLink;

  const CallPersonScreen({
    super.key,
    required this.personRef,
    this.sharedByHandle,
    this.onSignInRequested,
    this.allowArenaProfileLink = true,
  });

  @override
  State<CallPersonScreen> createState() => _CallPersonScreenState();
}

class _CallPersonScreenState extends State<CallPersonScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadPerson(widget.personRef);
    });
  }

  Future<void> _respond(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final result = await showCallResponseSheet(context: context, entry: entry);
    if (result != null && mounted) {
      await provider.loadPerson(widget.personRef, force: true);
    }
  }

  Future<void> _setFollowing(PersonDetail detail) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final following = !detail.viewerIsFollowing;
    try {
      await provider.setFollowing(detail, following);
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: following ? 'Following' : 'Unfollowed',
        subtitle:
            following
                ? 'Their calls will now appear in Following.'
                : 'This caller was removed from your feed.',
      );
    } on CallsException catch (error) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not update follow',
        subtitle: error.message,
      );
    } catch (_) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not update follow',
        subtitle: 'Please try again.',
      );
    }
  }

  CallReceipt _receiptFor(CallsProvider provider, CallFeedEntry entry) =>
      CallReceipt.fromEntry(
        entry,
        shareUrl: provider.shareLinkForCall(entry.call.id),
      );

  /// The rematch is built **from the receipt**, not from the raw call, because
  /// the receipt is the artefact the loop produces and it is the thing a person
  /// is answering. One construction path, so the button's visibility and the
  /// sheet's contents can never disagree.
  RematchOffer _offerFor(CallsProvider provider, CallFeedEntry entry) =>
      RematchOffer.fromReceipt(
        _receiptFor(provider, entry),
        opponentUserId: entry.author.id,
        marketAcceptsNewCalls: entry.market.status.acceptsNewCalls,
        viewerUserId: provider.viewerUserId,
      );

  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      receipt: _receiptFor(provider, entry),
    );
  }

  Future<void> _rematch(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final result = await showRematchSheet(
      context: context,
      offer: _offerFor(provider, entry),
    );
    if (result == null || !mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Rematch sent to @${entry.author.handle}. '
          'Nothing was staked and nothing was funded.',
        ),
      ),
    );
    await provider.loadPerson(widget.personRef, force: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Caller',
          style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
        ),
      ),
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          final detail = provider.personDetail(widget.personRef);
          if (detail == null) {
            if (provider.isLoadingPerson(widget.personRef)) {
              return const CallsLoadingView(rows: 2);
            }
            if (provider.isOffline) {
              return CallsOfflineView(
                onRetry:
                    () => provider.loadPerson(widget.personRef, force: true),
              );
            }
            return CallsErrorView(
              message:
                  provider.personError(widget.personRef) ??
                  'We couldn\'t find that person.',
              onRetry: () => provider.loadPerson(widget.personRef, force: true),
            );
          }
          return _body(provider, detail);
        },
      ),
    );
  }

  Widget _body(CallsProvider provider, PersonDetail detail) {
    final person = detail.person;

    // The record is derived from the calls actually on this page, by
    // `deriveCallOutcome` — the only permitted derivation (contract §3).
    // Nothing here decides an outcome; it only counts the ones the venue
    // produced.
    final record = PersonRecord.fromEntries(detail.calls);

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
      children: [
        if (widget.sharedByHandle != null)
          CallsNotice(
            icon: 'share-outline',
            color: AppColors.textSecondary,
            message: 'Shared with you by @${widget.sharedByHandle}.',
          ),
        Row(
          children: [
            AppAvatar(
              initials: person.initials,
              imageUrl: person.avatarUrl,
              size: 56,
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '@${person.handle}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ),
            ),
            if (provider.viewerUserId != person.id) ...[
              SizedBox(width: 8.w),
              SizedBox(
                width: 112.w,
                child: ChallengeButton(
                  label: detail.viewerIsFollowing ? 'Following' : 'Follow',
                  isLoading: provider.isFollowBusy(person.id),
                  blurRadius: false,
                  createNewChallenge: () => _setFollowing(detail),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 14.h),

        // Lifetime totals, from the server's own aggregate. Shown as counts
        // first — hits AND misses — with a percentage only once there is
        // enough settled history for one to be honest.
        _LifetimeSummary(person: person),

        SizedBox(height: 14.h),
        CategoryRecordCard(record: record, personName: person.displayName),
        SizedBox(height: 6.h),
        Text(
          'Counted from the calls on this page. '
          'Void calls count as neither correct nor incorrect.',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 11.sp),
        ),

        if (widget.allowArenaProfileLink && person.walletAddress != null) ...[
          SizedBox(height: 10.h),
          TextButton(
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (_) => CallerProfileScreen(
                          walletAddress: person.walletAddress!,
                        ),
                  ),
                ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: AppColors.primary,
            ),
            child: Text(
              'They also have a linked wallet — open their arena profile',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
            ),
          ),
        ],

        SizedBox(height: 18.h),
        if (detail.calls.isEmpty)
          const CallsEmptyView(
            title: 'Nothing on record yet',
            message: 'When they make a call, it shows up here.',
          )
        else
          for (final entry in detail.calls)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CallCard(
                    entry: entry,
                    showAuthor: false,
                    onOpenCall:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => CallDetailScreen(callId: entry.call.id),
                          ),
                        ),
                    onOpenMarket:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => MarketDetailScreen(
                                  marketId: entry.market.id,
                                ),
                          ),
                        ),
                    onRespond:
                        entry.author.id == provider.viewerUserId
                            ? null
                            : () => _respond(entry),
                    onShareReceipt: () => _shareReceipt(entry),
                  ),
                  // Renders nothing unless the call actually settled and it is
                  // somebody else's — a rematch answers a result.
                  _RematchRow(
                    offer: _offerFor(provider, entry),
                    onPressed: () => _rematch(entry),
                  ),
                ],
              ),
            ),

        if (detail.calls.isNotEmpty)
          Center(
            child: TextButton(
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => CallDetailScreen(
                            callId: detail.calls.first.call.id,
                          ),
                    ),
                  ),
              child: Text(
                'Open their latest call',
                style: TextStyle(fontSize: 12.sp, color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }
}

/// The person's lifetime totals as the repository reports them.
///
/// `Person.settledCalls` excludes VOID from both the numerator and the
/// denominator (`calls_repository.dart`), so misses are exactly
/// `settledCalls - correctCalls` — which is why this can, and does, always
/// print the misses next to the hits. The percentage is held back below
/// [kMinimumDecidedCallsForAccuracy] for the same reason the category record
/// holds it back.
class _LifetimeSummary extends StatelessWidget {
  final Person person;

  const _LifetimeSummary({required this.person});

  @override
  Widget build(BuildContext context) {
    final decided = person.settledCalls;
    final correct = person.correctCalls;
    final incorrect = decided - correct;
    final honest = decided >= kMinimumDecidedCallsForAccuracy;

    if (decided <= 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: CallBadge(
          label: 'No settled calls yet',
          color: AppColors.textSecondary,
          icon: 'award-outline',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            CallBadge(
              label: '$correct correct',
              color: AppColors.success,
              icon: 'check-outline',
            ),
            // There is no branch that can drop this one.
            CallBadge(
              label: '$incorrect incorrect',
              color: AppColors.error,
              icon: 'cross-outline',
            ),
            if (honest)
              CallBadge(
                label:
                    '${CallsFormat.probability(person.accuracy)} lifetime '
                    'accuracy',
                color: AppColors.textSecondary,
                icon: 'award-outline',
              ),
          ],
        ),
        SizedBox(height: 6.h),
        Text(
          honest
              ? 'Lifetime, across $decided decided calls. Void excluded.'
              : 'Lifetime, across $decided decided '
                  '${decided == 1 ? 'call' : 'calls'} — too few to put a '
                  'percentage on. Void excluded.',
          style: TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11.sp,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// Spacing wrapper so the button contributes no height when it renders nothing.
class _RematchRow extends StatelessWidget {
  final RematchOffer offer;
  final VoidCallback onPressed;

  const _RematchRow({required this.offer, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (!offer.isAvailable) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RematchButton(offer: offer, onPressed: onPressed),
      ),
    );
  }
}
