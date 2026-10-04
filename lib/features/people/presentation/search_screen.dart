/// One search across people and markets.
///
/// People come from the server's directory (`people.search`) — by handle or
/// name, never by wallet. Markets are filtered from the catalog the Markets
/// tab already loads, with the same eligibility rules it uses
/// ([discoveryMarkets]), so a market found here is one you could call.
///
/// Nothing is suggested before you type: an empty query shows an empty page
/// and a sentence, not a ranked list pretending to be "trending".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/widgets/person_row.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class PeopleSearchScreen extends StatefulWidget {
  /// Debounce for the server query. Tests pass [Duration.zero].
  final Duration debounce;
  const PeopleSearchScreen({
    super.key,
    this.debounce = const Duration(milliseconds: 300),
  });

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  static final _fieldText = GoogleFonts.montserrat(
    fontSize: 14,
    color: AppColors.textPrimary,
  );
  static const _marketLimit = 20;

  final _field = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _peopleQuery;
  List<PersonCard>? _people;
  String? _peopleError;
  bool _searchingPeople = false;
  final _requestedPrices = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final trimmed = value.trim().replaceFirst(RegExp(r'^@+'), '');
    if (trimmed.isEmpty) {
      setState(() {
        _peopleQuery = null;
        _people = null;
        _peopleError = null;
        _searchingPeople = false;
      });
      return;
    }
    _debounce = Timer(widget.debounce, () => _searchPeople(value));
  }

  Future<void> _searchPeople(String query) async {
    final provider = context.read<CallsProvider>();
    if (!provider.supportsPeople) return;
    setState(() {
      _peopleQuery = query;
      _searchingPeople = true;
      _peopleError = null;
    });
    try {
      final people = await provider.searchPeople(query);
      // A slower answer to an older query never replaces a newer one.
      if (!mounted || _peopleQuery != query) return;
      setState(() => _people = people);
    } on CallsException catch (e) {
      if (!mounted || _peopleQuery != query) return;
      setState(() => _peopleError = e.message);
    } catch (_) {
      if (!mounted || _peopleQuery != query) return;
      setState(() => _peopleError = const CallsFailure().message);
    } finally {
      if (mounted && _peopleQuery == query) {
        setState(() => _searchingPeople = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallsProvider>();
    final styles = AppTextStyles.textTheme;
    final term = _query.trim();
    final markets =
        term.isEmpty
            ? const <VenueMarket>[]
            : discoveryMarkets(
              provider.openMarkets,
              window: MarketDiscoveryWindow.all,
              query: term,
            );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const BasilIcon(
            'arrow-left-outline',
            size: 24,
            color: AppColors.textPrimary,
          ),
        ),
        title: Text('Search', style: styles.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          TextField(
            controller: _field,
            autofocus: true,
            onChanged: _onChanged,
            style: _fieldText,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'People or predictions',
              hintStyle: _fieldText.copyWith(color: AppColors.textSecondary),
              prefixIcon: const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 9, 0),
                child: BasilIcon(
                  'search-outline',
                  size: 19,
                  color: Color(0xFF7B8290),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 42,
                minHeight: 48,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.fromLTRB(0, 15, 14, 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (term.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: ChumbucketStateView(
                artwork: ChumbucketStateArtwork.search,
                message: 'Find people and markets',
                semanticsHint:
                    'Search a name or @handle, or words from a market’s '
                    'question.',
              ),
            )
          else ...[
            _SectionTitle('People'),
            const SizedBox(height: 8),
            ..._peopleSection(provider, styles),
            const SizedBox(height: 24),
            _SectionTitle('Markets'),
            const SizedBox(height: 8),
            ..._marketsSection(provider, styles, markets),
          ],
        ],
      ),
    );
  }

  List<Widget> _peopleSection(CallsProvider provider, TextTheme styles) {
    if (!provider.supportsPeople) {
      return [
        Text(
          'People search isn’t available in this build.',
          style: styles.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ];
    }
    final people = _people;
    return [
      if (_searchingPeople)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(color: AppColors.primary),
        ),
      if (_peopleError != null)
        _SearchMiss(
          offline: provider.isOffline,
          text:
              provider.isOffline
                  ? 'You’re offline'
                  : 'Couldn’t search people',
          detail: _peopleError!,
        )
      else if (people != null && people.isEmpty && !_searchingPeople)
        Text(
          'No one matches “${_query.trim()}”.',
          style: styles.bodyMedium?.copyWith(color: AppColors.textSecondary),
        )
      else if (people != null && people.isNotEmpty)
        PersonRowGroup(
          rows: [
            for (final person in people)
              PersonRow(
                person: person,
                showFollowing: true,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CallPersonScreen(personRef: person.id),
                      ),
                    ),
              ),
          ],
        ),
    ];
  }

  List<Widget> _marketsSection(
    CallsProvider provider,
    TextTheme styles,
    List<VenueMarket> markets,
  ) {
    if (provider.openMarkets.isEmpty) {
      if (provider.isLoadingOpenMarkets) {
        return const [LinearProgressIndicator(color: AppColors.primary)];
      }
      if (provider.openMarketsError != null) {
        return [
          _SearchMiss(
            offline: provider.isOffline,
            text:
                provider.isOffline
                    ? 'You’re offline'
                    : 'Couldn’t load markets',
            detail: provider.openMarketsError!,
          ),
        ];
      }
    }
    if (markets.isEmpty) {
      return [
        Text(
          'No open market asks about “${_query.trim()}”.',
          style: styles.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ];
    }
    final shown = markets.take(_marketLimit).toList();
    // Prices for the rows on screen only, through the provider's own cache —
    // the same per-row request the Markets tab makes.
    for (final market in shown) {
      if (!_requestedPrices.add(market.id)) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !provider.isLoadingMarket(market.id)) {
          provider.loadMarketDetail(market.id);
        }
      });
    }
    return [
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              CallMarketCard(
                market: shown[i],
                sharePrice: provider.marketDetail(shown[i].id)?.sharePrice,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => MarketDetailScreen(marketId: shown[i].id),
                      ),
                    ),
              ),
              if (i < shown.length - 1)
                const ColoredBox(
                  color: AppColors.surface,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, color: AppColors.divider),
                  ),
                ),
            ],
          ],
        ),
      ),
      if (markets.length > shown.length) ...[
        const SizedBox(height: 8),
        Text(
          'Showing ${shown.length} of ${markets.length}. Add a word to narrow it.',
          style: styles.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: AppTextStyles.questionTitle.copyWith(
        fontSize: 17,
        letterSpacing: 0,
      ),
    ),
  );
}

/// A section that could not be searched: an icon and a few words. Typing
/// again searches again; there is no retry button.
class _SearchMiss extends StatelessWidget {
  const _SearchMiss({
    required this.text,
    required this.detail,
    required this.offline,
  });
  final String text;
  final String detail;
  final bool offline;

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    hint: CallsErrorView.isHumanReason(detail) ? detail : null,
    excludeSemantics: true,
    child: Row(
      children: [
        BasilIcon(
          offline ? 'cloud-off-outline' : 'info-triangle-outline',
          size: 18,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
