import 'package:flutter/material.dart';
import 'package:chumbucket/shared/screens/home/widgets/overlapping_profile_avatars.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_sheet_content.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';

/// An earlier SOL escrow challenge (Settings → History), with its settle
/// actions for the witness. Wave design and overlapping avatars.
class ResolveChallengeSheet extends StatefulWidget {
  final Map<String, dynamic> challenge;
  final Function(Map<String, dynamic>, bool) onMarkCompleted;

  const ResolveChallengeSheet({
    super.key,
    required this.challenge,
    required this.onMarkCompleted,
  });

  @override
  State<ResolveChallengeSheet> createState() => _ResolveChallengeSheetState();
}

class _ResolveChallengeSheetState extends State<ResolveChallengeSheet> {
  /// Helper method to shorten wallet address in the same format used elsewhere
  String _shortenAddress(String address) {
    if (address.length <= 14) return address;
    final start = address.substring(0, 6);
    final end = address.substring(address.length - 4);
    return '$start...$end';
  }

  /// Format amount to display nicely (avoid rounding errors like 0.05 -> 0.1)
  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final value =
        (amount is num)
            ? amount.toDouble()
            : double.tryParse(amount.toString()) ?? 0.0;
    // Remove trailing zeros and limit to 4 decimal places
    if (value == value.truncate()) {
      return value.truncate().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  /// Close the sheet, then hand the verdict to the settle flow. The flow
  /// reports the real outcome (wallet approval, then Solana); nothing here
  /// claims success before the transaction exists.
  void _safeMarkCompleted(Map<String, dynamic> challenge, bool completed) {
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onMarkCompleted(challenge, completed);
  }

  @override
  Widget build(BuildContext context) {
    final status =
        (widget.challenge['status'] as String?)?.toLowerCase() ?? 'pending';
    // Use shared utility for consistent status handling
    final isResolvable = ChallengeStatusUtils.isResolvable(status);
    // Get friend name from challenge data - try multiple keys since different sources use different names
    final friendRaw =
        (widget.challenge['friendName'] as String?) ??
        (widget.challenge['participantId'] as String?) ??
        (widget.challenge['witness_address'] as String?) ??
        'Unknown';
    final amount = widget.challenge['amount'];
    final amountText = _formatAmount(amount);

    // This is the reference sheet itself (irfan/img2.jpeg): a muted caption
    // over the amount as the hero, and the two avatars straddling the wave
    // rather than sitting below it in the body. An earlier escrow challenge:
    // the caption says what the amount is, SOL locked in escrow.
    return ChumbucketWavySheet(
      title: isResolvable ? 'In escrow' : 'Staked',
      value: '$amountText SOL',
      headerLeading: FutureBuilder<String>(
        future: AddressNameResolver.resolveDisplayName(friendRaw),
        builder:
            (context, snapshot) => OverlappingProfileAvatars(
              userImagePath: 'assets/images/ai_gen/profile_images/1.png',
              friendImagePath: 'assets/images/ai_gen/profile_images/2.png',
              friendDisplayName: snapshot.data ?? _shortenAddress(friendRaw),
            ),
      ),
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ResolveSheetContent(
              challenge: widget.challenge,
              isPending: isResolvable,
              isWitness: widget.challenge['isCurrentUserWitness'] == true,
              onMarkCompleted: _safeMarkCompleted,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showResolveChallengeSheet(
  BuildContext context, {
  required Map<String, dynamic> challenge,
  required Function(Map<String, dynamic>, bool) onMarkCompleted,
}) => showChumbucketWavySheet<void>(
  context: context,
  builder:
      (_) => ResolveChallengeSheet(
        challenge: challenge,
        onMarkCompleted: onMarkCompleted,
      ),
);
