/// Public continuity for the canonical person. Wallets are never identity,
/// and the public record counts only visible public free calls.
library;

import 'dart:async';

import 'package:chumbucket/features/trust/presentation/safety_actions_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/services/push_registration.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_header.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_stats_card.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/presentation/widgets/credibility_strip.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:chumbucket/features/record/data/category_record.dart';
import 'package:chumbucket/features/rematch/data/rematch_offer.dart';
import 'package:chumbucket/features/rematch/presentation/rematch_sheet.dart';
import 'package:chumbucket/features/rematch/presentation/widgets/rematch_button.dart';
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
  int _selectedTab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadPerson(widget.personRef);
    });
  }

  Future<void> _respond(CallFeedEntry entry, [CallResponseKind? kind]) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final result = await showCallResponseSheet(
      context: context,
      entry: entry,
      initialKind: kind,
    );
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
      if (following) unawaited(PushRegistration.afterSocialAction(context));
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
      entry: entry,
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
        title: Text('Profile', style: AppTextStyles.textTheme.titleLarge),
        actions: [
          // Report, mute or block — never on your own profile.
          Consumer<CallsProvider>(
            builder: (context, provider, _) {
              final person = provider.personDetail(widget.personRef)?.person;
              if (person == null || person.id == provider.viewerUserId) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'More',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed:
                    () => showSafetyActions(
                      context,
                      SafetyTarget(
                        personId: person.id,
                        handle: person.handle,
                        displayName: person.displayName,
                      ),
                    ),
                icon: const BasilIcon(
                  'other-1-outline',
                  color: AppColors.textPrimary,
                ),
              );
            },
          ),
        ],
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
    final styles = AppTextStyles.textTheme;
    // Only visible public free calls contribute to the per-category view.
    // Person's lifetime fields do not carry a visibility scope in this model.
    final record = PersonRecord.fromEntries(
      detail.calls.where((e) => e.call.visibility == CallVisibility.public),
    );
    final publicRecord = detail.record;
    final followCounts = PeopleFormat.followCounts(
      detail.followerCount,
      detail.followingCount,
    );
    final isSelf = provider.viewerUserId == person.id;
    final open = detail.calls.where((e) => !e.outcome.isSettled).toList();
    final settled = detail.calls.where((e) => e.outcome.isSettled).toList();
    final listed = _selectedTab == 0 ? open : settled;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await provider.loadPerson(widget.personRef, force: true);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.sharedByHandle != null)
            CallsNotice(
              icon: 'share-outline',
              color: AppColors.textSecondary,
              message: 'Shared with you by @${widget.sharedByHandle}.',
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ColoredBox(
              color: AppColors.outlineVariant,
              child: Column(
                children: [
                  ProfileHeader(
                    username: person.displayName,
                    handle: person.handle,
                    bio: person.bio ?? '',
                    profileImagePath: person.avatarUrl,
                    canEdit: false,
                    onEditProfile: () {},
                    footer:
                        isSelf && followCounts == null
                            ? null
                            : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (followCounts != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    followCounts,
                                    style: styles.bodyMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                if (!isSelf)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 48,
                                      ),
                                      child: ChallengeButton(
                                        label:
                                            detail.viewerIsFollowing
                                                ? 'Following'
                                                : 'Follow',
                                        isLoading: provider.isFollowBusy(
                                          person.id,
                                        ),
                                        blurRadius: false,
                                        createNewChallenge:
                                            () => _setFollowing(detail),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                  ),
                  // The server's public record when it sent one; otherwise
                  // the older summary computed from the visible calls.
                  if (publicRecord != null)
                    CredibilityStrip(
                      record: publicRecord,
                      joinedAtUtc: person.joinedAtUtc,
                    )
                  else
                    ProfileStatsCard(entries: detail.calls),
                ],
              ),
            ),
          ),
          // What the record counts lives behind the record's info icon.
          // Saved calls stay on screen; offline is only a small pill.
          if (provider.isOffline) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: ChumbucketOfflinePill(),
            ),
          ],
          // No wallet, stakes or arena money profile in a public identity panel.
          // allowArenaProfileLink is retained only for constructor compatibility.
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ChumbucketTabs(
              labels: [
                'Open · ${open.length}',
                'Settled · ${settled.length}',
                'Record',
              ],
              selectedIndex: _selectedTab,
              onSelected: (index) => setState(() => _selectedTab = index),
            ),
          ),
          const SizedBox(height: 16),
          if (_selectedTab == 2) ...[
            for (final category in record.categories)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.label, style: styles.titleMedium),
                    const SizedBox(height: 12),
                    for (final tally in category.tallies)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${tally.count} ${tally.outcome.label.toLowerCase()}',
                          style: styles.bodyMedium,
                        ),
                      ),
                    Text(
                      '${category.pending} awaiting result · ${category.decided} decided',
                      style: styles.bodySmall,
                    ),
                  ],
                ),
              ),
            if (record.isEmpty)
              const CallsEmptyView(
                artwork: ChumbucketStateArtwork.record,
                title: 'Nothing on record yet',
                message: 'No public free calls are available to score.',
              ),
          ] else if (detail.calls.isEmpty)
            const CallsEmptyView(
              artwork: ChumbucketStateArtwork.record,
              title: 'Nothing on record yet',
              message: 'When they make a call, it shows up here.',
            )
          else if (listed.isEmpty)
            CallsEmptyView(
              artwork: ChumbucketStateArtwork.record,
              title:
                  _selectedTab == 0 ? 'No open calls' : 'Nothing settled yet',
              message:
                  _selectedTab == 0
                      ? 'Every call here has a venue result. See Settled.'
                      : 'No call here has a venue result yet. Closing time alone '
                          'does not settle a call.',
            )
          else
            for (final entry in listed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
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
                                  (_) =>
                                      CallDetailScreen(callId: entry.call.id),
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
                      onBack:
                          entry.author.id == provider.viewerUserId
                              ? null
                              : () => _respond(entry, CallResponseKind.back),
                      onFade:
                          entry.author.id == provider.viewerUserId
                              ? null
                              : () => _respond(entry, CallResponseKind.fade),
                      onShareReceipt: () => _shareReceipt(entry),
                    ),
                    _RematchRow(
                      offer: _offerFor(provider, entry),
                      onPressed: () => _rematch(entry),
                    ),
                  ],
                ),
              ),
        ],
      ),
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
