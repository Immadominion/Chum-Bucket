/// Picks the market to call, then hands off to the composer.
///
/// Shows each market's status and venue attribution but **no price**: the price
/// belongs on the market detail, next to the rules and the data age, where it
/// can be read in context rather than skimmed off a list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

Future<void> showMarketPickerSheet({required BuildContext context}) {
  return showChumbucketWavySheet<void>(
    context: context,
    builder: (_) => const MarketPickerSheet(),
  );
}

class MarketPickerSheet extends StatefulWidget {
  const MarketPickerSheet({super.key});

  @override
  State<MarketPickerSheet> createState() => _MarketPickerSheetState();
}

class _MarketPickerSheetState extends State<MarketPickerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
  }

  Future<void> _pick(VenueMarket market) async {
    final provider = context.read<CallsProvider>();
    final detail = await provider.loadMarketDetail(market.id, force: true);
    if (!mounted) return;
    final entry = await showCallComposer(
      context: context,
      market: detail?.market ?? market,
      snapshot: detail?.snapshot,
      sharePrice: detail?.sharePrice,
    );
    if (entry != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ChumbucketWavySheet(
      title: 'What are you calling?',
      subtitle: 'Free, timestamped, and locked the moment you send it.',
      height: MediaQuery.sizeOf(context).height * 0.78,
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          if (!provider.isSignedIn) return const CallsSignedOutView();
          if (provider.isLoadingOpenMarkets && provider.openMarkets.isEmpty) {
            return const CallsLoadingView(rows: 3);
          }
          if (provider.openMarkets.isEmpty) {
            final error = provider.openMarketsError;
            if (provider.isOffline) {
              return CallsOfflineView(
                onRetry: () => provider.loadOpenMarkets(force: true),
              );
            }
            if (error != null) {
              return CallsErrorView(
                message: error,
                onRetry: () => provider.loadOpenMarkets(force: true),
              );
            }
            return const CallsEmptyView(
              title: 'Nothing open right now',
              message:
                  'No market is accepting calls at the moment. Check back '
                  'shortly.',
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 20.h),
            itemCount: provider.openMarkets.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              final market = provider.openMarkets[index];
              return _MarketRow(market: market, onTap: () => _pick(market));
            },
          );
        },
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final VenueMarket market;
  final VoidCallback onTap;

  const _MarketRow({required this.market, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    market.question,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.sp,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 6.h,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MarketStatusBadge(status: market.status),
                      DemoVenueBadge(venue: market.venue),
                      CallBadge(
                        label: CallsFormat.untilClose(market.closesAtUtc),
                        color: AppColors.textSecondary,
                        icon: 'clock-outline',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            BasilIcon(
              'caret-right-outline',
              size: 18.w,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
