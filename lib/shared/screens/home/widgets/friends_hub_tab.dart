/// The Friends tab: the people you follow and your friends from the wallet
/// app, in one list. The leaderboard opens from the header's award icon.
///
/// Adding a friend follows them (add_friend_sheet.dart), so "Friends" and
/// "Following" are one list here rather than two tabs that showed the same
/// people with different explanations. Friends from the original wallet app
/// sit under them, with their avatars, when a wallet is connected.
///
/// No paragraphs: an obvious Add a friend row at the top, the people, and —
/// with nobody yet — the Plankton & Karen people scene with one line and one
/// button.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/leaderboard_view.dart';
import 'package:chumbucket/features/people/presentation/search_screen.dart';
import 'package:chumbucket/features/people/presentation/widgets/person_row.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class FriendsHubTab extends StatefulWidget {
  final int refreshKey;
  final VoidCallback onAddFriend;

  /// A tapped friend's row (`name`, `walletAddress`, `userId`).
  final void Function(Map<String, String> friend) onFriendSelected;
  final Widget Function(BuildContext, int) buildViewMoreItem;
  final VoidCallback onViewAllChallenges;
  final Future<void> Function(Map<String, dynamic>, bool)
  onMarkChallengeCompleted;
  const FriendsHubTab({
    super.key,
    required this.refreshKey,
    required this.onAddFriend,
    required this.onFriendSelected,
    required this.buildViewMoreItem,
    required this.onViewAllChallenges,
    required this.onMarkChallengeCompleted,
  });

  @override
  State<FriendsHubTab> createState() => _FriendsHubTabState();
}

class _FriendsHubTabState extends State<FriendsHubTab>
    with AutomaticKeepAliveClientMixin {
  /// Bumped by pull-to-refresh so the invitations read again.
  int _refreshTick = 0;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh(CallsProvider? calls) async {
    setState(() => _refreshTick++);
    if (calls != null && calls.isSignedIn && calls.supportsPeople) {
      await calls.loadFollowing(force: true);
    }
  }

  void _openLeaderboard() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()));

  void _openPerson(String personId) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CallPersonScreen(personRef: personId)),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final calls = context.watch<CallsProvider?>();
    final wallet = context.watch<MwaAuthProvider?>()?.walletAddress;
    // The record-based Leaderboard exists only where the live people layer
    // does. A build without it (the seeded mock) shows no ranking at all
    // rather than an invented one.
    final people = calls?.supportsPeople == true;
    final signedIn = calls?.isSignedIn == true;

    // The people you follow, from the server's own follow list.
    final following = people && signedIn ? calls!.following : null;
    if (people &&
        signedIn &&
        following == null &&
        !calls!.isLoadingFollowing &&
        calls.followingError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) calls.loadFollowing();
      });
    }
    final Widget? followingSection;
    if (people) {
      followingSection =
          following == null || following.isEmpty
              ? null
              : _FollowingRows(people: following, onOpen: _openPerson);
    } else {
      followingSection =
          signedIn
              ? _FeedPeople(
                key: ValueKey('feed-people-${calls!.viewerUserId}'),
                provider: calls,
                refreshTick: _refreshTick,
                onOpen: _openPerson,
              )
              : null;
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ChumbucketAppHeader(
              title: 'Friends',
              showAccountActions: false,
              // The leaderboard is one tap away as an icon, not a second
              // tab row under the title.
              actions: [
                if (people)
                  IconButton(
                    key: const ValueKey('friends-leaderboard'),
                    tooltip: 'Leaderboard',
                    onPressed: _openLeaderboard,
                    icon: const BasilIcon(
                      'award-outline',
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
              ],
              onSearchTap:
                  calls == null
                      ? null
                      : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PeopleSearchScreen(),
                        ),
                      ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FriendsTab(
                // Keyed by wallet only: a refresh (resume, a friend added)
                // reads again in place and keeps the list on screen, rather
                // than building a new, empty tab.
                key: ValueKey('friends-$wallet'),
                refreshKey: widget.refreshKey,
                onAddFriend: widget.onAddFriend,
                onFriendSelected: widget.onFriendSelected,
                buildViewMoreItem: widget.buildViewMoreItem,
                onViewAllChallenges: widget.onViewAllChallenges,
                onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
                showChallengesPreview: false,
                bottomPadding: 140,
                followingSection: followingSection,
                followingEmpty:
                    !people || !signedIn ? null : following?.isEmpty,
                followingLoading:
                    people &&
                    signedIn &&
                    following == null &&
                    calls!.followingError == null,
                followingError:
                    people && signedIn && following == null
                        ? calls!.followingError
                        : null,
                onRefresh: () => _refresh(calls),
                invitations:
                    signedIn
                        ? _CallInvitations(
                          key: ValueKey('invitations-${calls!.viewerUserId}'),
                          provider: calls,
                          refreshToken: '${widget.refreshKey}-$_refreshTick',
                        )
                        : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The people you follow, each with their public record.
class _FollowingRows extends StatelessWidget {
  const _FollowingRows({required this.people, required this.onOpen});
  final List<PersonCard> people;
  final void Function(String personId) onOpen;

  @override
  Widget build(BuildContext context) => PersonRowGroup(
    rows: [
      for (final person in people)
        PersonRow(person: person, onTap: () => onOpen(person.id)),
    ],
  );
}

/// A build without the people layer (the seeded mock) has no follow
/// directory: it lists the people behind your Following feed instead.
class _FeedPeople extends StatefulWidget {
  const _FeedPeople({
    super.key,
    required this.provider,
    required this.refreshTick,
    required this.onOpen,
  });
  final CallsProvider provider;
  final int refreshTick;
  final void Function(String personId) onOpen;

  @override
  State<_FeedPeople> createState() => _FeedPeopleState();
}

class _FeedPeopleState extends State<_FeedPeople> {
  late Future<CallFeedPage> _page = _read();

  Future<CallFeedPage> _read() => widget.provider.repository.fetchFeed(
    mode: CallFeedMode.following,
    viewerUserId: widget.provider.viewerUserId,
  );

  @override
  void didUpdateWidget(covariant _FeedPeople oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _page = _read();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CallFeedPage>(
    future: _page,
    builder: (context, snapshot) {
      final entries = snapshot.data?.entries ?? const <CallFeedEntry>[];
      final people = <String, Person>{
        for (final entry in entries) entry.author.id: entry.author,
      };
      if (people.isEmpty) return const SizedBox.shrink();
      return Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final person in people.values)
              Semantics(
                button: true,
                label: '${person.displayName}, @${person.handle}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => widget.onOpen(person.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        PersonAvatar(
                          initials: person.initials,
                          imageUrl: person.avatarUrl,
                          size: 44,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                person.displayName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '@${person.handle}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const BasilIcon(
                          'arrow-right-outline',
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Dares to call a market, from people you know. Free; they open the source
/// call, where you take a side. A dare whose source call is private, deleted
/// or unreadable is left out rather than shown as a broken row.
class _CallInvitations extends StatefulWidget {
  final CallsProvider provider;

  /// Changes when the tab is refreshed (resume, pull): the dares read again
  /// while the ones already shown stay on screen.
  final String refreshToken;
  const _CallInvitations({
    super.key,
    required this.provider,
    required this.refreshToken,
  });
  @override
  State<_CallInvitations> createState() => _CallInvitationsState();
}

class _CallInvitationsState extends State<_CallInvitations> {
  late Future<List<CallDetail>> _invitations;
  @override
  void initState() {
    super.initState();
    _invitations = _read();
  }

  @override
  void didUpdateWidget(covariant _CallInvitations oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new future keeps FutureBuilder's last data until it answers.
    if (oldWidget.refreshToken != widget.refreshToken) _invitations = _read();
  }

  Future<List<CallDetail>> _read() async {
    final viewer = widget.provider.viewerUserId;
    final repository = widget.provider.repository;
    final invites = await repository.fetchInvitations(viewerUserId: viewer);
    final details = await Future.wait(
      invites.where((invite) => invite.toUserId == viewer).map((invite) async {
        try {
          final detail = await repository.fetchCall(
            callId: invite.sourceCallId,
            viewerUserId: viewer,
          );
          if (detail.entry.author.id != invite.fromUserId ||
              detail.entry.market.id != invite.marketId) {
            return null;
          }
          return detail;
        } catch (_) {
          return null;
        } // Private/deleted/blocked source stays hidden.
      }),
    );
    return details.whereType<CallDetail>().toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CallDetail>>(
      future: _invitations,
      builder: (context, snapshot) {
        // Loading or failed: nothing here. The list below stays usable and a
        // pull re-reads it; a dare is never worth a spinner or an error card.
        final invitations = snapshot.data ?? const [];
        if (invitations.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final detail in invitations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _InvitationRow(detail: detail),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({required this.detail});
  final CallDetail detail;

  @override
  Widget build(BuildContext context) {
    final author = detail.entry.author;
    final market = detail.entry.market;
    final title = '${author.displayName} invited you to call';
    return Semantics(
      button: true,
      label:
          '$title. ${market.venue.isDemo ? 'Demo data. ' : ''}'
          '${market.question}. Free.',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => CallDetailScreen(callId: detail.entry.call.id),
                ),
              ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PersonAvatar(
                      initials: author.initials,
                      imageUrl: author.avatarUrl,
                      size: 44,
                    ),
                    const Positioned(
                      right: -3,
                      bottom: -3,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: AppColors.surface,
                        child: BasilIcon(
                          'fire-solid',
                          size: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${market.venue.isDemo ? 'DEMO DATA · ' : ''}'
                        '${market.question}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Free',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.pinkInk,
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
}
