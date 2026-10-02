/// People ranked by their public call record — the People hub's Leaderboard.
///
/// What it will not do, by construction of the data it is handed:
///
/// * rank anybody below the minimum decided sample (they are listed under
///   "Building a record", unnumbered, with what they still need);
/// * show a percentage the server did not send;
/// * rank by money. There is no P&L or stake on any row.
///
/// Every row names its denominator, and the server's own ranking rule sits
/// under the window chips so the order is explainable.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/widgets/people_format.dart';
import 'package:chumbucket/features/people/presentation/widgets/person_row.dart';

class LeaderboardView extends StatefulWidget {
  /// Clearance for the floating tab bar when embedded in the shell.
  final double bottomPadding;
  const LeaderboardView({super.key, this.bottomPadding = 140});

  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  LeaderboardWindow _window = LeaderboardWindow.month;

  void _select(LeaderboardWindow window) {
    setState(() => _window = window);
    context.read<CallsProvider>().loadLeaderboard(window);
  }

  Future<void> _refresh() =>
      context.read<CallsProvider>().loadLeaderboard(_window, force: true);

  void _open(String personId) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CallPersonScreen(personRef: personId)),
  );

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallsProvider>();
    final board = provider.leaderboard(_window);
    final error = provider.leaderboardError(_window);
    final loading = provider.isLoadingLeaderboard(_window);
    final styles = AppTextStyles.textTheme;
    // Nothing held, nothing in flight, nothing failed: first open, or the
    // viewer changed and the provider dropped the old board. Read it.
    if (board == null && !loading && error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) provider.loadLeaderboard(_window);
      });
    }

    final children = <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final window in LeaderboardWindow.values)
            Semantics(
              button: true,
              selected: window == _window,
              label: 'Leaderboard for ${window.phrase}',
              onTap: () => _select(window),
              excludeSemantics: true,
              child: MarketFilterChip(
                label: window.label,
                selected: window == _window,
                onPressed: () => _select(window),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        board?.rule ??
            'Ranked by accuracy on calls the venue decided. Free public calls only.',
        style: styles.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 16),
    ];

    if (board == null) {
      if (loading) {
        children.add(
          const SizedBox(height: 320, child: CallsLoadingView(rows: 3)),
        );
      } else if (provider.isOffline && error != null) {
        children.add(CallsOfflineView(onRetry: _refresh));
      } else if (error != null) {
        children.add(CallsErrorView(message: error, onRetry: _refresh));
      }
    } else {
      if (loading) {
        children.add(const LinearProgressIndicator(color: AppColors.primary));
      }
      if (error != null) {
        children.add(
          CallsNotice(
            icon: 'info-triangle-outline',
            color: AppColors.onWarningContainer,
            message: 'Showing the last board. $error',
            actionLabel: 'Retry',
            onAction: _refresh,
          ),
        );
      }
      children.add(
        _YourRank(board: board, signedIn: provider.isSignedIn, onOpen: _open),
      );
      children.add(const SizedBox(height: 20));
      if (board.isEmpty) {
        children.add(
          CallsEmptyView(
            artwork: ChumbucketStateArtwork.record,
            title: 'No records in ${board.window.phrase} yet',
            message:
                'Nobody has a call the venue decided in this window. '
                'Rankings appear once people do — nothing here is invented.',
            actionLabel:
                board.window == LeaderboardWindow.all ? null : 'Show all time',
            onAction:
                board.window == LeaderboardWindow.all
                    ? null
                    : () => _select(LeaderboardWindow.all),
          ),
        );
      } else {
        children.add(Text('Ranked', style: styles.titleMedium));
        children.add(const SizedBox(height: 8));
        if (board.ranked.isEmpty) {
          children.add(
            Text(
              'Nobody has ${board.minimumDecided} decided calls in '
              '${board.window.phrase} yet, so nobody is ranked.',
              style: styles.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          );
        } else {
          children.add(
            PersonRowGroup(
              rows: [
                for (final row in board.ranked)
                  PersonRow(
                    person: row.person,
                    rank: row.rank,
                    highlighted: row.person.id == board.viewer?.person.id,
                    onTap: () => _open(row.person.id),
                  ),
              ],
            ),
          );
        }
        if (board.building.isNotEmpty) {
          children.addAll([
            const SizedBox(height: 24),
            Text('Building a record', style: styles.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Fewer than ${board.minimumDecided} decided calls, so no '
              'percentage and no rank yet. Most decided first.',
              style: styles.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            PersonRowGroup(
              rows: [
                for (final row in board.building)
                  PersonRow(
                    person: row.person,
                    detail:
                        '${PeopleFormat.recordShort(row.record)} · '
                        '${PeopleFormat.toRank(row.record) ?? ''}',
                    highlighted: row.person.id == board.viewer?.person.id,
                    onTap: () => _open(row.person.id),
                  ),
              ],
            ),
          ]);
        }
      }
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: ListView(
        key: const PageStorageKey('people-leaderboard'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 0, 16, widget.bottomPadding),
        children: children,
      ),
    );
  }
}

/// The pinned "Your rank" card. Signed out, it invites sign-in rather than
/// showing an empty rank; signed in, it always says where the viewer stands
/// and what they still need — never somebody else's numbers.
class _YourRank extends StatelessWidget {
  final Leaderboard board;
  final bool signedIn;
  final void Function(String personId) onOpen;

  const _YourRank({
    required this.board,
    required this.signedIn,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final viewer = board.viewer;
    final String headline;
    final String body;
    if (!signedIn || viewer == null) {
      headline = 'Your rank';
      body = 'Sign in to see where your calls place you.';
    } else if (viewer.rank != null) {
      headline = 'You’re #${viewer.rank}';
      body =
          '${PeopleFormat.recordShort(viewer.record)} in ${board.window.phrase}.';
    } else if (viewer.record.decided == 0) {
      headline = 'Not ranked yet';
      body =
          'No call of yours was decided in ${board.window.phrase}. '
          'Make calls; ${board.minimumDecided} decided calls earn a rank.';
    } else {
      headline = 'Not ranked yet';
      body =
          '${PeopleFormat.recordShort(viewer.record)}. '
          '${PeopleFormat.toRank(viewer.record) ?? ''}.';
    }
    final VoidCallback onTap =
        !signedIn || viewer == null
            ? () => requestCallSignIn(context)
            : () => onOpen(viewer.person.id);
    return Semantics(
      container: true,
      button: true,
      label: '$headline. $body',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: AppTextStyles.questionTitle.copyWith(
                    fontSize: 18,
                    letterSpacing: 0,
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: styles.bodyMedium?.copyWith(
                    color: AppColors.onPrimaryContainer,
                    height: 1.5,
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
