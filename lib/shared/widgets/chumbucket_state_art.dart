import 'package:flutter/material.dart';

/// A visual vocabulary, not application state. The caller still decides what
/// happened and supplies the accessible heading, explanation and next action.
enum ChumbucketStateArtwork {
  calls('empty_calls'),
  people('people'),
  search('search'),
  inbox('inbox'),
  record('record'),
  challenges('challenges'),
  waiting('waiting'),
  offline('offline'),
  error('error'),
  access('access'),
  success('success');

  const ChumbucketStateArtwork(this.fileName);

  final String fileName;
  String get assetPath => 'assets/images/states/$fileName.png';
}

/// Small, transparent, logo-derived scenes. Never use artwork in place of
/// state text, a progress indicator, a transaction status or venue evidence.
///
/// This widget owns no padding or minimum screen height, so short sheets stay
/// content-sized. Artwork is decorative: the adjacent live text is accessible.
class ChumbucketStateArt extends StatelessWidget {
  const ChumbucketStateArt(this.artwork, {super.key, this.size = 144});

  const ChumbucketStateArt.compact(this.artwork, {super.key}) : size = 96;

  final ChumbucketStateArtwork artwork;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: Image.asset(
        artwork.assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // Enough for a 144dp image at 3x, without decoding eleven full masters.
        cacheWidth: 512,
        excludeFromSemantics: true,
        // Keep the message and recovery action available on a bad asset load.
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    ),
  );
}
