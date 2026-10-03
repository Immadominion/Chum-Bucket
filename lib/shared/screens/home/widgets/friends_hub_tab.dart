import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/people/presentation/leaderboard_view.dart';
import 'package:chumbucket/features/people/presentation/search_screen.dart';
import 'package:chumbucket/features/people/presentation/widgets/person_row.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
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
  int _selectedIndex = 0;
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final calls = context.watch<CallsProvider?>();
    final wallet = context.watch<MwaAuthProvider?>()?.walletAddress;
    // The record-based Leaderboard exists only where the live people layer
    // does. A build without it (the seeded mock) shows no ranking at all
    // rather than an invented one.
    final people = calls?.supportsPeople == true;
    final labels = ['Friends', 'Following', if (people) 'Leaderboard'];
    final selected = _selectedIndex < labels.length ? _selectedIndex : 0;
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ChumbucketTabs(
                labels: labels,
                selectedIndex: selected,
                onSelected: (index) => setState(() => _selectedIndex = index),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: IndexedStack(
              index: selected,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FriendsTab(
                    key: ValueKey('${widget.refreshKey}-$wallet'),
                    onAddFriend: widget.onAddFriend,
                    onFriendSelected: widget.onFriendSelected,
                    buildViewMoreItem: widget.buildViewMoreItem,
                    onViewAllChallenges: widget.onViewAllChallenges,
                    onMarkChallengeCompleted: widget.onMarkChallengeCompleted,
                    showChallengesPreview: false,
                    bottomPadding: 140,
                    invitations:
                        calls?.isSignedIn == true
                            ? _CallInvitations(
                              key: ValueKey(
                                'invitations-${calls!.viewerUserId}-${widget.refreshKey}',
                              ),
                              provider: calls,
                            )
                            : null,
                  ),
                ),
                if (people)
                  _FollowingList(
                    key: ValueKey('following-list-${calls!.viewerUserId}'),
                    provider: calls,
                  )
                else
                  _FollowingPeople(
                    key: ValueKey('following-${calls?.viewerUserId}'),
                    provider: calls,
                  ),
                if (people) const LeaderboardView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The people you follow, from the server's own follow list
/// (`people.following`) — complete, not inferred from recent calls — each
/// with their public record.
class _FollowingList extends StatelessWidget {
  final CallsProvider provider;
  const _FollowingList({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    if (!provider.isSignedIn) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
        children: [
          _PeopleNotice(
            artwork: ChumbucketStateArtwork.access,
            title: 'Keep up with your people',
            message: 'Sign in to see the people you follow.',
            action: () => requestCallSignIn(context),
            actionLabel: 'Sign in',
          ),
        ],
      );
    }
    final following = provider.following;
    final error = provider.followingError;
    final loading = provider.isLoadingFollowing;
    // First open, or the list was dropped after a follow change: read it.
    if (following == null && !loading && error == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.loadFollowing(),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => provider.loadFollowing(force: true),
      child: ListView(
        key: const PageStorageKey('following-list'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('People you follow', style: styles.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Their calls fill your Following feed on Home. Following is '
            'separate from friendship.',
            style: styles.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(color: AppColors.primary),
          if (error != null)
            _PeopleNotice(
              artwork: ChumbucketStateArtwork.error,
              title: 'Following unavailable',
              message: error,
              action: () => provider.loadFollowing(force: true),
              actionLabel: 'Try again',
            )
          else if (following != null && following.isEmpty)
            const _PeopleNotice(
              artwork: ChumbucketStateArtwork.people,
              title: 'You don’t follow anyone yet',
              message:
                  'Find people on the Leaderboard, in Search, or from any call '
                  'on Home, then tap Follow.',
            )
          else if (following != null)
            PersonRowGroup(
              rows: [
                for (final person in following)
                  PersonRow(
                    person: person,
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (_) => CallPersonScreen(personRef: person.id),
                          ),
                        ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The repository exposes a following feed, not a complete follow directory.
/// Label that scope explicitly and leave feed mode/scroll state untouched.
class _FollowingPeople extends StatefulWidget {
  final CallsProvider? provider;
  const _FollowingPeople({super.key, this.provider});
  @override
  State<_FollowingPeople> createState() => _FollowingPeopleState();
}

class _FollowingPeopleState extends State<_FollowingPeople> {
  Future<CallFeedPage>? _page;
  @override
  void initState() {
    super.initState();
    _page = _read();
  }

  Future<CallFeedPage>? _read() {
    final provider = widget.provider;
    if (provider == null || !provider.isSignedIn) return null;
    return provider.repository.fetchFeed(
      mode: CallFeedMode.following,
      viewerUserId: provider.viewerUserId,
    );
  }

  Future<void> _refresh() async {
    final next = _read();
    setState(() {
      _page = next;
    });
    try {
      await _page;
    } catch (_) {
      /* FutureBuilder renders the error. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    if (_page == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
        children: [
          _PeopleNotice(
            artwork: ChumbucketStateArtwork.access,
            title: 'Keep up with your people',
            message: 'Sign in to see people from your Following feed.',
            action:
                widget.provider == null
                    ? null
                    : () => requestCallSignIn(context),
            actionLabel: 'Sign in',
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: FutureBuilder<CallFeedPage>(
        future: _page,
        builder: (context, snapshot) {
          final entries = snapshot.data?.entries ?? const <CallFeedEntry>[];
          final people = <String, Person>{
            for (final entry in entries) entry.author.id: entry.author,
          };
          return ListView(
            key: const PageStorageKey('following-people'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text('People in your Following feed', style: styles.titleLarge),
              const SizedBox(height: 8),
              Text(
                'From the latest calls. Following is separate from friendship.',
                style: styles.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(color: AppColors.primary),
              if (snapshot.hasError)
                _PeopleNotice(
                  artwork: ChumbucketStateArtwork.error,
                  title: 'Following unavailable',
                  message:
                      snapshot.error is CallsException
                          ? (snapshot.error as CallsException).message
                          : 'Could not load people. Try again.',
                  action: _refresh,
                  actionLabel: 'Try again',
                ),
              if (snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError &&
                  people.isEmpty)
                const _PeopleNotice(
                  artwork: ChumbucketStateArtwork.people,
                  title: 'No recent calls here',
                  message:
                      'Follow someone from their call or profile. Their calls will appear on Home.',
                ),
              if (snapshot.data?.fromCache == true)
                Text(
                  'Showing saved people. Pull down to refresh.',
                  style: styles.bodySmall,
                ),
              Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final person in people.values)
                      ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: AppAvatar(
                          initials: person.initials,
                          imageUrl: person.avatarUrl,
                          size: 48,
                          backgroundColor: AppColors.primaryContainer,
                          textColor: AppColors.onPrimaryContainer,
                        ),
                        title: Text(
                          person.displayName,
                          style: styles.titleMedium,
                        ),
                        subtitle: Text(
                          '@${person.handle}',
                          style: styles.bodySmall,
                        ),
                        trailing: const BasilIcon('arrow-right-outline'),
                        onTap:
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) =>
                                        CallPersonScreen(personRef: person.id),
                              ),
                            ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CallInvitations extends StatefulWidget {
  final CallsProvider provider;
  const _CallInvitations({super.key, required this.provider});
  @override
  State<_CallInvitations> createState() => _CallInvitationsState();
}

class _CallInvitationsState extends State<_CallInvitations> {
  late Future<List<CallDetail?>> _invitations;
  @override
  void initState() {
    super.initState();
    _invitations = _read();
  }

  Future<List<CallDetail?>> _read() async {
    final viewer = widget.provider.viewerUserId;
    final repository = widget.provider.repository;
    final invites = await repository.fetchInvitations(viewerUserId: viewer);
    return Future.wait(
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
  }

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return FutureBuilder<List<CallDetail?>>(
      future: _invitations,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _PeopleNotice(
              title: 'Call invitations unavailable',
              message: 'Could not load your invitations.',
              action: () {
                final next = _read();
                setState(() {
                  _invitations = next;
                });
              },
              actionLabel: 'Try again',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(color: AppColors.primary),
          );
        }
        final invitations = snapshot.data ?? const [];
        if (invitations.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Call invitations', style: styles.titleMedium),
            const SizedBox(height: 8),
            for (final detail in invitations)
              if (detail == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: _PeopleNotice(
                    title: 'Invitation unavailable',
                    message:
                        'The source call may be private, deleted or unavailable.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: AppAvatar(
                        initials: detail.entry.author.initials,
                        imageUrl: detail.entry.author.avatarUrl,
                        size: 48,
                        backgroundColor: AppColors.surface,
                        textColor: AppColors.textPrimary,
                      ),
                      title: Text(
                        '${detail.entry.author.displayName} invited you to call',
                        style: styles.titleSmall,
                      ),
                      subtitle: Text(
                        '${detail.entry.market.venue.isDemo ? 'DEMO DATA · ' : ''}'
                        'Free invitation · no payment\nOpen the source call to take a side.',
                        style: styles.bodySmall?.copyWith(
                          color: AppColors.onPrimaryContainer,
                        ),
                      ),
                      trailing: const BasilIcon('arrow-right-outline'),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => CallDetailScreen(
                                    callId: detail.entry.call.id,
                                  ),
                            ),
                          ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PeopleNotice extends StatelessWidget {
  final ChumbucketStateArtwork? artwork;
  final String title;
  final String message;
  final VoidCallback? action;
  final String? actionLabel;
  const _PeopleNotice({
    this.artwork,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel,
  });
  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (artwork != null) ...[
            Center(child: ChumbucketStateArt.compact(artwork!)),
            const SizedBox(height: 12),
          ],
          Text(title, style: styles.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: styles.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppColors.textPrimary,
              ),
              onPressed: action,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
