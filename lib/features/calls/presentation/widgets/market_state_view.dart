/// One state screen for market discovery: the brand art, one short line and
/// at most one action. Used for no matches, an empty catalog, and a catalog
/// or market that could not load with nothing cached to show instead.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:google_fonts/google_fonts.dart';

export 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

class MarketStateView extends StatelessWidget {
  const MarketStateView({
    super.key,
    required this.artwork,
    required this.line,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final ChumbucketStateArtwork artwork;

  /// The whole message. One short line: what happened, not why or how.
  final String line;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The smaller art, for a sheet rather than a whole screen.
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 32,
        vertical: compact ? 16 : 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          compact
              ? ChumbucketStateArt.compact(artwork)
              : ChumbucketStateArt(artwork),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'PPNeueMachina',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.pinkInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}
