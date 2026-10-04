/// Settings → History: the earlier Chumbucket products, kept readable.
///
/// SOL escrow challenges and Arena football predictions came before calls.
/// They no longer sit in the main app (no tab, no badge, no "Challenge"
/// button, and nothing anywhere can start a new escrow), but everything a
/// person had there is still reachable here — including settling an escrow
/// that still holds SOL, which its witness does with their wallet, because
/// that is their money.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
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
          // Earlier Chumbucket features: nothing new starts here, and what
          // you already have stays yours (an open escrow can still be
          // settled by its witness, Arena winnings can still be claimed).
          // That is read out per row rather than printed as a paragraph.
          _HistoryRow(
            icon: 'lock-time-outline',
            title: 'Escrow challenges',
            hint:
                onOpenEscrowChallenges == null
                    ? 'Open this from the Profile tab, Settings, History.'
                    : 'Your SOL escrow challenges with friends. Any still '
                        'open are settled here by their witness.',
            onTap: onOpenEscrowChallenges,
          ),
          _HistoryRow(
            icon: 'hotspot-outline',
            title: 'Arena predictions',
            hint:
                'Your football predictions, their original terms, and any '
                'winnings to claim.',
            onTap:
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const MyPotsScreen())),
          ),
          _HistoryRow(
            icon: 'notification-outline',
            title: 'Earlier notices',
            hint: 'Notifications from the original challenge and Arena system.',
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
    required this.hint,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: onTap != null,
        label: title,
        hint: hint,
        excludeSemantics: true,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    BasilIcon(icon, size: 22, color: AppColors.textPrimary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      const BasilIcon(
                        'arrow-right-outline',
                        size: 18,
                        color: AppColors.textPrimary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
