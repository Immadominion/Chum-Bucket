/// Market detail.
///
/// The five things this screen exists to show, in this order of importance:
///
/// 1. the venue's **exact** resolution criteria, never paraphrased and never
///    truncated behind a "read more" that hides the part that matters;
/// 2. the close time;
/// 3. how old the price is;
/// 4. the YES/NO price;
/// 5. who the venue is — and, for `fixture`, that it is demo data.
///
/// What it will not show before the viewer has locked their own call: how the
/// crowd called it. The repository withholds that, so this screen physically
/// cannot render it early.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class MarketDetailScreen extends StatefulWidget {
  final String marketId;
  final VoidCallback? onSignInRequested;

  const MarketDetailScreen({
    super.key,
    required this.marketId,
    this.onSignInRequested,
  });

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CallsProvider>().loadMarketDetail(widget.marketId);
      }
    });
  }

  Future<void> _compose(MarketDetail detail) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final entry = await showCallComposer(
      context: context,
      market: detail.market,
      snapshot: detail.snapshot,
      sharePrice: detail.sharePrice,
    );
    if (entry != null && mounted) {
      await _openCall(entry.call.id);
      if (mounted) {
        await provider.loadMarketDetail(widget.marketId, force: true);
      }
    }
  }

  Future<void> _openCall(String callId) => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => CallDetailScreen(callId: callId)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Market',
          style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
        ),
      ),
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          final detail = provider.marketDetail(widget.marketId);
          if (detail == null) {
            if (provider.isLoadingMarket(widget.marketId)) {
              return const CallsLoadingView(rows: 2);
            }
            if (provider.isOffline) {
              return CallsOfflineView(
                onRetry:
                    () =>
                        provider.loadMarketDetail(widget.marketId, force: true),
              );
            }
            return CallsErrorView(
              message:
                  provider.marketError(widget.marketId) ??
                  'We couldn\'t load this market.',
              onRetry:
                  () => provider.loadMarketDetail(widget.marketId, force: true),
            );
          }
          return _body(provider, detail);
        },
      ),
    );
  }

  Widget _body(CallsProvider provider, MarketDetail detail) {
    final market = detail.market;
    final snapshot = detail.snapshot;
    final age = snapshot?.ageAt(DateTime.now());
    final stale = provider.isSnapshotStale(market.id);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
            children: [
              if (provider.isOffline)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: CallsNotice.offline(
                    onRetry:
                        () => provider.loadMarketDetail(
                          widget.marketId,
                          force: true,
                        ),
                  ),
                ),
              if (market.venue.isDemo)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: CallsNotice.demoData(),
                ),

              Text(
                market.question,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20.sp,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  MarketStatusBadge(status: market.status),
                  CallBadge(
                    label: CallsFormat.untilClose(market.closesAtUtc),
                    color: AppColors.textSecondary,
                    icon: 'clock-outline',
                  ),
                  CallBadge(
                    label: CallsFormat.venueAttribution(market),
                    color:
                        market.venue.isDemo
                            ? AppColors.tertiary
                            : AppColors.textSecondary,
                    icon: 'info-circle-outline',
                  ),
                ],
              ),

              SizedBox(height: 16.h),
              _PriceBlock(
                snapshot: snapshot,
                age: age,
                stale: stale,
                isPanta: market.venue == MarketVenue.panta,
                sharePrice: detail.sharePrice,
              ),

              SizedBox(height: 16.h),
              _RulesBlock(market: market),

              SizedBox(height: 16.h),
              _FactsBlock(market: market),

              if (detail.viewerCall != null) ...[
                SizedBox(height: 18.h),
                Text(
                  'Your call',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8.h),
                CallCard(
                  entry: detail.viewerCall!,
                  showAuthor: false,
                  onOpenCall: () => _openCall(detail.viewerCall!.call.id),
                ),
              ],

              // Only ever non-null once the viewer has locked. Before that the
              // repository does not hand it over at all.
              if (detail.crowdSplit != null) ...[
                SizedBox(height: 18.h),
                _CrowdBlock(split: detail.crowdSplit!, market: market),
              ],
            ],
          ),
        ),
        if (market.status.acceptsNewCalls && detail.viewerCall == null)
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 16.h),
            child: ChallengeButton(
              label: 'Make my call',
              blurRadius: false,
              createNewChallenge: () => _compose(detail),
            ),
          ),
      ],
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final bool isPanta;
  final SharePriceSnapshot? sharePrice;
  final MarketSnapshot? snapshot;
  final Duration? age;
  final bool stale;

  const _PriceBlock({
    this.isPanta = false,
    this.sharePrice,
    required this.snapshot,
    required this.age,
    required this.stale,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Venue price',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (stale)
                CallBadge(
                  label: 'Stale',
                  color: AppColors.warning,
                  icon: 'clock-outline',
                ),
            ],
          ),
          SizedBox(height: 10.h),
          if (isPanta) ...[
            Text(
              CallsFormat.nativePrices(sharePrice),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (sharePrice != null)
              Text(
                'Observed ${CallsFormat.timestampUtc(sharePrice!.observedAtUtc)}',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12.sp,
                ),
              ),
            Text(
              '${SharePriceSnapshot.attribution} · Indicative, not a trade quote',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12.sp),
            ),
            if (!(sharePrice?.isUsableAt(DateTime.now()) ?? false))
              Text(
                'Prices unavailable or stale — refresh before calling.',
                style: TextStyle(color: AppColors.warning, fontSize: 12.sp),
              ),
          ] else if (snapshot == null)
            Text(
              'No price published yet. You can still call it — your call just '
              'locks without an entry probability.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.sp,
                height: 1.4,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _PricePill(
                    side: Side.yes,
                    value: snapshot.yesProbability,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _PricePill(
                    side: Side.no,
                    value: snapshot.noProbability,
                  ),
                ),
              ],
            ),
          SizedBox(height: 10.h),
          if (!isPanta)
            Text(
              CallsFormat.dataAge(age),
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12.sp),
            ),
          if (snapshot != null)
            Text(
              'Observed ${CallsFormat.timestampUtc(snapshot.observedAtUtc)}'
              '${snapshot.source.isDemo ? ' · demo source' : ''}',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11.sp),
            ),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final Side side;
  final double value;

  const _PricePill({required this.side, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = side == Side.yes ? AppColors.success : AppColors.error;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 14.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side.wire,
            style: TextStyle(
              color: color,
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            CallsFormat.probability(value),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The venue's exact resolution criteria, in full. Never paraphrased, never
/// summarised, never collapsed behind a fold.
class _RulesBlock extends StatelessWidget {
  final VenueMarket market;

  const _RulesBlock({required this.market});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BasilIcon(
                'book-check-outline',
                size: 15.w,
                color: AppColors.textTertiary,
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  'HOW IT RESOLVES — THE VENUE\'S EXACT WORDS',
                  maxLines: 2,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          SelectableText(
            market.rulesText,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.sp,
              height: 1.55,
            ),
          ),
          if (market.resolutionSource != null) ...[
            SizedBox(height: 10.h),
            Text(
              'Resolution source: ${market.resolutionSource}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactsBlock extends StatelessWidget {
  final VenueMarket market;

  const _FactsBlock({required this.market});

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) => Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Venue', market.venue.label),
          row('Venue status', market.rawStatus),
          row(
            'Closes',
            market.closesAtUtc == null
                ? 'Not published'
                : CallsFormat.timestampUtc(market.closesAtUtc!),
          ),
          row('Last synced', CallsFormat.timestampUtc(market.lastSyncedAtUtc)),
          row('Venue market id', market.venueMarketId),
        ],
      ),
    );
  }
}

/// How the community called it. Rendered only after the viewer's own call is
/// locked, so it can never anchor the call it is meant to follow.
class _CrowdBlock extends StatelessWidget {
  final CrowdSplit split;
  final VenueMarket market;

  const _CrowdBlock({required this.split, required this.market});

  @override
  Widget build(BuildContext context) {
    final share = split.yesShare;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOW EVERYONE ELSE CALLED IT',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Shown now because your call is already locked.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11.sp),
          ),
          SizedBox(height: 12.h),
          if (share == null)
            Text(
              'You are the only one on record here so far.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${market.labelFor(Side.yes)} · ${split.yesCalls}',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${market.labelFor(Side.no)} · ${split.noCalls}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
