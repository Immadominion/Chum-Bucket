/// Settings → History: the earlier Chumbucket products, kept readable.
///
/// SOL escrow challenges and Arena football predictions came before calls.
/// They no longer sit in the main app (no tab, no badge, no "Challenge"
/// button), but everything a person had there is still reachable here —
/// including resolving, claiming and refunding an escrow that is still open,
/// because that is their money.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/arena/presentation/screens/arena_notifications_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class LegacyHistoryScreen extends StatelessWidget {
  const LegacyHistoryScreen({super.key, this.onOpenEscrowChallenges});

  /// Opens the escrow challenge list with its resolve/claim actions (the home
  /// shell owns those). Null where the shell is not available.
  final VoidCallback? onOpenEscrowChallenges;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('History'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Earlier Chumbucket features. They are read-only now: nothing new '
            'can be started here, but anything you already have is still yours '
            'to finish, claim or refund.',
            style: styles.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _HistoryRow(
            icon: 'contacts-outline',
            title: 'Escrow challenges',
            detail:
                onOpenEscrowChallenges == null
                    ? 'Open History from your Profile to see your SOL escrow challenges.'
                    : 'Your SOL escrow challenges with friends, including any '
                        'still waiting to be resolved, claimed or refunded.',
            onTap: onOpenEscrowChallenges,
          ),
          _HistoryRow(
            icon: 'hotspot-outline',
            title: 'Arena predictions',
            detail:
                'Your football predictions, their original terms, and any winnings to claim.',
            onTap:
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const MyPotsScreen())),
          ),
          _HistoryRow(
            icon: 'notification-outline',
            title: 'Earlier notices',
            detail:
                'Notifications from the original challenge and Arena system.',
            onTap:
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ArenaNotificationsScreen(),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.all(16),
          leading: BasilIcon(icon, color: AppColors.textPrimary),
          title: Text(title, style: styles.titleMedium),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              detail,
              style: styles.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          trailing:
              onTap == null
                  ? null
                  : const BasilIcon(
                    'arrow-right-outline',
                    color: AppColors.textPrimary,
                  ),
        ),
      ),
    );
  }
}
