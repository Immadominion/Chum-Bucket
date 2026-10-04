/// One state screen for market discovery: the brand art, one short line and
/// at most one action. Used for no matches, an empty catalog, and a catalog
/// or market that could not load with nothing cached to show instead.
///
/// Drawn by the app's one state screen ([ChumbucketStateView], fleet/ux-states)
/// so Markets, the picker and market detail read like every other empty,
/// error or offline state: same scene sizes, same primary button.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/shared/widgets/chumbucket_state_view.dart';

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
    child: Semantics(
      liveRegion: true,
      child: ChumbucketStateView(
        artwork: artwork,
        message: line,
        actionLabel: actionLabel,
        onAction: onAction,
        compact: compact,
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compact ? 16 : 32,
        ),
      ),
    ),
  );
}
