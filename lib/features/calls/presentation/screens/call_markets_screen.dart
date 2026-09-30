import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Public discovery: there is something useful here before the first follow.
/// Opening a market never asks for identity. Locking a call does.
class CallMarketsScreen extends StatefulWidget {
  const CallMarketsScreen({super.key});

  @override
  State<CallMarketsScreen> createState() => _CallMarketsScreenState();
}

class _CallMarketsScreenState extends State<CallMarketsScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallsProvider>();
    final markets = provider.openMarkets.where(
      (market) => market.question.toLowerCase().contains(_query.toLowerCase()),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: const InputDecoration(
              hintText: 'Find a question to call',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (provider.isLoadingOpenMarkets &&
                  provider.openMarkets.isEmpty) {
                return const CallsLoadingView(rows: 3);
              }
              if (provider.openMarketsError != null &&
                  provider.openMarkets.isEmpty) {
                return CallsErrorView(
                  message: provider.openMarketsError!,
                  onRetry: () => provider.loadOpenMarkets(force: true),
                );
              }
              if (markets.isEmpty) {
                return CallsEmptyView(
                  title:
                      _query.isEmpty
                          ? 'No markets ready for calls'
                          : 'No matching questions',
                  message:
                      _query.isEmpty
                          ? 'Calls need an open market with current venue prices. '
                              'Refresh to check again.'
                          : 'Try another search or refresh the venue catalog.',
                  actionLabel: 'Refresh',
                  onAction: () => provider.loadOpenMarkets(force: true),
                );
              }
              final rows = markets.toList(growable: false);
              return RefreshIndicator(
                onRefresh: () => provider.loadOpenMarkets(force: true),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final market = rows[index];
                    return CallMarketCard(
                      market: market,
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) =>
                                      MarketDetailScreen(marketId: market.id),
                            ),
                          ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
