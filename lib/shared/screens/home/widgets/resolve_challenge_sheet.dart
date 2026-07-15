import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';
import 'dart:io';
import 'package:chumbucket/shared/screens/home/widgets/overlapping_profile_avatars.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_sheet_header.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_sheet_content.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';

/// Modal bottom sheet for resolving challenges with wave design and overlapping avatars
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

  /// Safe wrapper for the completion callback that shows success feedback
  void _safeMarkCompleted(
    Map<String, dynamic> challenge,
    bool completed,
  ) async {
    if (!mounted) return;

    try {
      // Close the modal first
      Navigator.of(context).pop();

      // Execute the completion callback
      widget.onMarkCompleted(challenge, completed);

      // Show success feedback after a short delay to ensure modal is closed
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                completed
                    ? 'Challenge completed successfully!'
                    : 'Challenge marked as failed',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: completed ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    } catch (e) {
      // Show error feedback if something goes wrong
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update challenge: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

    // Calculate responsive height with constraints
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.86; // Max 86% of screen height
    final minHeight = 320.h;
    final preferredHeight = isResolvable ? 510.h : 320.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(43.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        children: [
          // Top section with gradient background and wave
          Container(
            height: 300.h.clamp(200.h, maxHeight * 0.5),
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(43.r),
                topRight: Radius.circular(43.r),
              ),
            ),
            child: Stack(
              children: [
                // Gradient header
                ResolveSheetHeader(amountText: amountText),

                // White wavy section with smooth waves
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ClipPath(
                    clipper: DetailedWaveClipper(),
                    child: Container(
                      height: 300.h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            offset: const Offset(0, -2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Overlapping profile images positioned in the wave
                Positioned(
                  bottom: 32.h,
                  left: 0,
                  right: 0,
                  child: FutureBuilder<String>(
                    future: AddressNameResolver.resolveDisplayName(friendRaw),
                    builder: (context, snapshot) {
                      final friendDisplayName =
                          snapshot.data ?? _shortenAddress(friendRaw);

                      return OverlappingProfileAvatars(
                        userImagePath:
                            'assets/images/ai_gen/profile_images/1.png',
                        friendImagePath:
                            'assets/images/ai_gen/profile_images/2.png',
                        friendDisplayName: friendDisplayName,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom section with challenge details and buttons
          // isCurrentUserWitness flag is set in challenges_preview.dart
          ResolveSheetContent(
            challenge: widget.challenge,
            isPending: isResolvable,
            isWitness: widget.challenge['isCurrentUserWitness'] == true,
            onMarkCompleted: _safeMarkCompleted,
          ),
        ],
      ),
    );
  }
}

Future<void> showResolveChallengeSheet(
  BuildContext context, {
  required Map<String, dynamic> challenge,
  required Function(Map<String, dynamic>, bool) onMarkCompleted,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.5),
    elevation: 0,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom:
                  Platform.isIOS
                      ? MediaQuery.of(context).padding.bottom + 10.h
                      : MediaQuery.of(context).padding.bottom + 20.h,
            ),
            child: ResolveChallengeSheet(
              challenge: challenge,
              onMarkCompleted: onMarkCompleted,
            ),
          ),
        ),
      );
    },
  );
}
