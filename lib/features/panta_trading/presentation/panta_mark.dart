/// Panta's attribution, as a compact mark rather than a sentence: the
/// wordmark "Panta", quiet, beside the actions Panta's terms ask it beside —
/// trading on Panta and publishing a market there. Nowhere else: a free
/// call, a card or a receipt carries no venue attribution.
///
/// No Panta logo ships in either repo, so the mark is text. Screen readers
/// hear the full attribution.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';

import '../data/panta_trading_models.dart' show pantaAttribution;

class PantaMark extends StatelessWidget {
  const PantaMark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: pantaAttribution,
    excludeSemantics: true,
    child: const Text(
      'Panta',
      key: ValueKey('panta-mark'),
      style: TextStyle(
        fontFamily: 'PPNeueMachina',
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: .2,
        height: 1.2,
        color: AppColors.textMuted,
      ),
    ),
  );
}
