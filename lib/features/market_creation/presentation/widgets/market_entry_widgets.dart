/// The two places market creation shows up outside its own screens: the
/// Markets tab's "Create a market" card, and "Proposed by @handle" on a live
/// market people proposed here.
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../data/market_creation_client.dart';
import '../../data/market_creation_models.dart';

/// "Can't find your question? Create a market."
class CreateMarketEntryCard extends StatelessWidget {
  const CreateMarketEntryCard({
    super.key,
    required this.onCreate,
    required this.onOpenMine,
  });

  final VoidCallback onCreate;
  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onCreate,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const BasilIcon(
                'add-outline',
                size: 22,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a market',
                    style: AppTextStyles.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Can’t find your question? Propose it, free.',
                    style: AppTextStyles.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenMine,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppColors.onPrimaryContainer,
              ),
              child: const Text('Yours'),
            ),
          ],
        ),
      ),
    ),
  );
}

typedef MarketProposerLookup =
    Future<MarketProposer?> Function(String venueMarketId);

/// Shared, cached `marketCreation.byMarket` reads.
///
/// Only a configured app (AppConfig loaded `dotenv`) reaches the network, so
/// widget tests that render a market never make a request.
class MarketProposerCache {
  MarketProposerCache._();
  static final instance = MarketProposerCache._();

  final Map<String, MarketProposer?> _known = {};
  final Map<String, Future<MarketProposer?>> _inflight = {};
  MarketCreationClient? _client;

  /// Replaceable in tests.
  MarketProposerLookup? lookupOverride;

  MarketProposer? cached(String venueMarketId) => _known[venueMarketId];
  bool has(String venueMarketId) => _known.containsKey(venueMarketId);

  Future<MarketProposer?> load(String venueMarketId) {
    if (_known.containsKey(venueMarketId)) {
      return Future.value(_known[venueMarketId]);
    }
    return _inflight[venueMarketId] ??= () async {
      try {
        final lookup = lookupOverride ?? _defaultLookup;
        final proposer = await lookup(venueMarketId);
        _known[venueMarketId] = proposer;
        return proposer;
      } catch (_) {
        return null; // Attribution is decoration; never block the market.
      } finally {
        _inflight.remove(venueMarketId);
      }
    }();
  }

  Future<MarketProposer?> _defaultLookup(String venueMarketId) async {
    if (!dotenv.isInitialized) return null;
    _client ??= MarketCreationClient.bff();
    return _client!.proposerOf(venueMarketId);
  }

  void clear() {
    _known.clear();
    _inflight.clear();
  }
}

/// "Proposed by @ada on Chumbucket", when someone here proposed this market.
class MarketProposerLine extends StatefulWidget {
  const MarketProposerLine({
    super.key,
    required this.venueMarketId,
    this.onOpenPerson,
  });
  final String venueMarketId;
  final void Function(MarketProposer proposer)? onOpenPerson;

  @override
  State<MarketProposerLine> createState() => _MarketProposerLineState();
}

class _MarketProposerLineState extends State<MarketProposerLine> {
  MarketProposer? _proposer;

  @override
  void initState() {
    super.initState();
    final cache = MarketProposerCache.instance;
    _proposer = cache.cached(widget.venueMarketId);
    if (!cache.has(widget.venueMarketId)) {
      unawaited(
        cache.load(widget.venueMarketId).then((p) {
          if (mounted && p != null) setState(() => _proposer = p);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final proposer = _proposer;
    if (proposer == null) return const SizedBox.shrink();
    final text = Text(
      'Proposed by ${proposer.atHandle} on Chumbucket',
      style: AppTextStyles.textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
    final open = widget.onOpenPerson;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child:
          open == null
              ? text
              : InkWell(
                onTap: () => open(proposer),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(alignment: Alignment.centerLeft, child: text),
                ),
              ),
    );
  }
}
