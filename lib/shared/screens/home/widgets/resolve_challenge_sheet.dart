import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui';
import 'package:chumbucket/shared/screens/home/widgets/overlapping_profile_avatars.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_sheet_header.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_sheet_content.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

/// Modal bottom sheet for resolving challenges with wave design and overlapping avatars
class ResolveChallengeSheet extends StatelessWidget {
  final Map<String, dynamic> challenge;
  final Function(Map<String, dynamic>, bool) onMarkCompleted;

  const ResolveChallengeSheet({
    super.key,
    required this.challenge,
    required this.onMarkCompleted,
  });

  /// Helper method to shorten wallet address in the same format used elsewhere
  String _shortenAddress(String address) {
    if (address.length <= 14) return address;
    final start = address.substring(0, 6);
    final end = address.substring(address.length - 4);
    return '$start...$end';
  }

  @override
  Widget build(BuildContext context) {
    final status = (challenge['status'] as String?)?.toLowerCase() ?? 'pending';
    final isPending = status == 'pending';
    final friendRaw = (challenge['friendName'] as String?) ?? 'Zara';
    final amount = challenge['amount'];
    final amountText = amount is num ? amount.toStringAsFixed(1) : '$amount';

    // Calculate responsive height with constraints
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.86; // Max 86% of screen height
    final minHeight = 320.h;
    final preferredHeight = isPending ? 510.h : 320.h;
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
          ResolveSheetContent(
            challenge: challenge,
            isPending: isPending,
            onMarkCompleted: onMarkCompleted,
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
          child: ResolveChallengeSheet(
            challenge: challenge,
            onMarkCompleted: onMarkCompleted,
          ),
        ),
      );
    },
  );
}
