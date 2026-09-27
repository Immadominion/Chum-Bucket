import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
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
                          ? 'Nothing open right now'
                          : 'No matching questions',
                  message: 'Try another search or refresh the venue catalog.',
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
                    return Card(
                      margin: EdgeInsets.zero,
                      color: AppColors.surface,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap:
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder:
                                    (_) =>
                                        MarketDetailScreen(marketId: market.id),
                              ),
                            ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                market.question,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  MarketStatusBadge(status: market.status),
                                  DemoVenueBadge(venue: market.venue),
                                  Text(market.venue.label),
                                  Text(
                                    CallsFormat.untilClose(market.closesAtUtc),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
