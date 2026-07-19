import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/data/match_arena_service.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

/// Pick an outcome bucket and stake USDC into the shared match pot. This is a
/// solo stake into a parimutuel pot, not a 1-v-1 friend dare.
class DareYourselfScreen extends StatefulWidget {
  final ArenaMatchEntry match;

  const DareYourselfScreen({super.key, required this.match});

  @override
  State<DareYourselfScreen> createState() => _DareYourselfScreenState();
}

class _DareYourselfScreenState extends State<DareYourselfScreen> {
  int? _selectedBucket;
  ArenaMarket? _selectedMarket;
  final TextEditingController _amountController = TextEditingController();
  bool _isSubmitting = false;
  String? _serviceError;

  @override
  void initState() {
    super.initState();
    // Default to the full-time Result market; the switcher can swap it.
    _selectedMarket = widget.match.resultMarket;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureService());
  }

  /// The markets shown in the switcher, in the backend's order but with the
  /// Result market pinned first.
  List<ArenaMarket> get _markets {
    final markets = List<ArenaMarket>.of(widget.match.markets);
    markets.sort((a, b) {
      if (a.kind == 'RESULT' && b.kind != 'RESULT') return -1;
      if (a.kind != 'RESULT' && b.kind == 'RESULT') return 1;
      return 0;
    });
    return markets;
  }

  void _selectMarket(ArenaMarket market) {
    if (_selectedMarket?.marketId == market.marketId) return;
    setState(() {
      _selectedMarket = market;
      // The outcomes differ per market, so any prior pick no longer applies.
      _selectedBucket = null;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _ensureService() async {
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final arena = Provider.of<ArenaProvider>(context, listen: false);
    if (arena.isArenaServiceReady) return;
    try {
      await arena.ensureArenaService(
        authProvider: authProvider,
        walletAddress: authProvider.walletAddress,
        rpcUrl: NetworkConfig.rpcUrl,
      );
      if (mounted) setState(() => _serviceError = null);
    } catch (e) {
      if (mounted) setState(() => _serviceError = e.toString());
    }
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  Future<void> _submit() async {
    final arena = Provider.of<ArenaProvider>(context, listen: false);
    final market = _selectedMarket;

    if (market == null) {
      SnackBarUtils.showError(
        context,
        title: 'No market to call',
        subtitle: 'This match isn\'t open for calls right now.',
      );
      return;
    }
    if (_selectedBucket == null) {
      SnackBarUtils.showError(
        context,
        title: 'Pick an outcome',
        subtitle: 'Choose an outcome before placing your call.',
      );
      return;
    }
    if (_amount <= 0) {
      SnackBarUtils.showError(
        context,
        title: 'Enter a stake',
        subtitle: 'Enter how much USDC you want to stake.',
      );
      return;
    }
    if (!arena.isArenaServiceReady) {
      await _ensureService();
      if (!mounted) return;
      if (!arena.isArenaServiceReady) {
        SnackBarUtils.showError(
          context,
          title: 'Wallet not ready',
          subtitle: _serviceError ?? 'Could not connect to your wallet yet.',
        );
        return;
      }
    }

    final selectedTotal = market.bucketByIndex(_selectedBucket!);
    final displayLabel = _bucketLabel(market, _selectedBucket!);
    // The market's own bucket label ("HOME"/"OVER"/...) for the social layer.
    final bucketLabel = selectedTotal?.bucket ?? displayLabel;

    setState(() => _isSubmitting = true);
    try {
      await arena.placeCall(
        match: widget.match,
        market: market,
        bucket: _selectedBucket!,
        bucketLabel: bucketLabel,
        amountUsdc: _amount,
        authProvider: Provider.of<MwaAuthProvider>(context, listen: false),
      );
      if (!mounted) return;
      SnackBarUtils.showSuccess(
        context,
        title: 'Call placed',
        subtitle: '${ArenaFormat.usdc(_amount)} staked on $displayLabel.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not place call',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markets = _markets;
    // Keep the selection valid if the market list changed under us.
    final market =
        _selectedMarket != null &&
                markets.any((m) => m.marketId == _selectedMarket!.marketId)
            ? _selectedMarket
            : (markets.isNotEmpty ? markets.first : null);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Make a call',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.match.fixture.competition,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  widget.match.fixture.title,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 24.h),
                if (markets.length > 1) ...[
                  Text(
                    'What do you want to call?',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildMarketSwitcher(markets, market),
                  SizedBox(height: 22.h),
                ],
                Text(
                  'Call an outcome',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12.h),
                if (market != null) _buildBucketPicker(market),
                if (market != null) ...[
                  SizedBox(height: 12.h),
                  _buildPickInsight(market),
                ],
                SizedBox(height: 28.h),
                Text(
                  'Your stake',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12.h),
                _buildAmountInput(),
                SizedBox(height: 12.h),
                _buildQuickStakeChips(),
                SizedBox(height: 16.h),
                if (market != null) ...[
                  _buildPayoutPreview(market),
                  SizedBox(height: 12.h),
                ],
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text(
                    'Your USDC moves into the shared pot the moment you sign - '
                    'never into anyone else\'s wallet. If your pick wins, come '
                    'back to claim your share.',
                    style: TextStyle(
                      fontSize: 11.5.sp,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                if (_serviceError != null) ...[
                  SizedBox(height: 12.h),
                  Text(
                    _serviceError!,
                    style: TextStyle(color: AppColors.error, fontSize: 12.sp),
                  ),
                ],
                SizedBox(height: 32.h),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Light segmented control to switch which market (Result / Over-Under /
  /// Handicap) you're calling. Only shown when a fixture has more than one.
  Widget _buildMarketSwitcher(List<ArenaMarket> markets, ArenaMarket? current) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(13.r),
      ),
      child: Row(
        children:
            markets.map((m) {
              final selected = current?.marketId == m.marketId;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _selectMarket(m),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10.r),
                      border:
                          selected
                              ? Border.all(color: AppColors.primary, width: 1.5)
                              : null,
                    ),
                    child: Text(
                      _marketTabLabel(m),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? AppColors.primary : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  /// A short tab label for the switcher, derived from the market. Kept plain
  /// and compact so three tabs fit on one row.
  String _marketTabLabel(ArenaMarket market) {
    switch (market.kind) {
      case 'RESULT':
        return 'Result';
      case 'OVER_UNDER':
        final line = market.line?.line;
        return line != null ? 'O/U ${_trimLine(line)}' : 'Over / Under';
      case 'HANDICAP':
        return 'Handicap';
      default:
        return market.label;
    }
  }

  /// "2.5" -> "2.5", "2.0" -> "2".
  String _trimLine(double value) =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();

  /// The chip label for one bucket. RESULT keeps its established HOME/DRAW/AWAY
  /// chips; line markets show the backend's plain label ("Over 2.5").
  String _bucketLabel(ArenaMarket market, int bucket) {
    if (!market.isLineMarket) {
      return ArenaFormat.bucketLabel(bucket);
    }
    return market.bucketByIndex(bucket)?.label ?? '?';
  }

  Widget _buildBucketPicker(ArenaMarket market) {
    return Row(
      children:
          market.buckets.map((total) {
            final bucket = total.bucketIndex;
            final selected = _selectedBucket == bucket;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedBucket = bucket),
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 4.w),
                  padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 6.w),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryContainer : Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(
                      color:
                          selected ? AppColors.primary : Colors.grey.shade300,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _bucketLabel(market, bucket),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.primary : Colors.black,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        ArenaFormat.usdcFromBaseUnits(total.stake),
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        ArenaFormat.percent(total.impliedProb),
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  // ── Live parimutuel projection (mirrors the web call screen) ──────────────
  // If your pick wins you get your stake back plus a pro-rata share of the
  // stake sitting on the OTHER outcomes (the pool backing against you), less a
  // 2.5% rake. Empty pool => nothing to win yet (first-caller case).

  static const int _rakeBps = 250; // 2.5%, taken from the other outcomes only

  double _poolOf(ArenaMarket market, int bucket) {
    final total = market.bucketByIndex(bucket);
    return total != null
        ? MatchArenaService.baseUnitsToUsdc(total.stake)
        : 0.0;
  }

  double _totalPool(ArenaMarket market) {
    var sum = 0.0;
    for (final b in market.buckets) {
      sum += MatchArenaService.baseUnitsToUsdc(b.stake);
    }
    return sum;
  }

  /// A plain phrase naming the picked outcome, used in the crowd/payout copy.
  /// For the Result market it's the team name (or "the draw"); for a line
  /// market it's the outcome's plain label ("Over 2.5").
  String _bucketPhrase(ArenaMarket market, int bucket) {
    if (!market.isLineMarket) {
      switch (bucket) {
        case MatchArenaService.bucketHome:
          return widget.match.fixture.home;
        case MatchArenaService.bucketAway:
          return widget.match.fixture.away;
        default:
          return 'the draw';
      }
    }
    return market.bucketByIndex(bucket)?.label ?? 'this outcome';
  }

  /// The "If … your profit" row label, phrased naturally per market.
  String _ifOutcomeLabel(ArenaMarket market, int bucket) {
    if (!market.isLineMarket) {
      return bucket == MatchArenaService.bucketDraw
          ? 'If it\'s a draw, your profit'
          : 'If ${_bucketPhrase(market, bucket)} wins, your profit';
    }
    return 'If ${_bucketPhrase(market, bucket)} is right, your profit';
  }

  /// Short, plain copy under the picker that reacts to the chosen outcome and
  /// how much of the crowd is already on it.
  Widget _buildPickInsight(ArenaMarket market) {
    final pick = _selectedBucket;
    if (pick == null) {
      return Text(
        'Tap an outcome above to see what you\'d win.',
        style: TextStyle(
          fontSize: 12.sp,
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final total = _totalPool(market);
    final prob = market.bucketByIndex(pick)?.impliedProb ?? 0.0;
    final pctText = ArenaFormat.percent(prob);
    final outcome = _bucketPhrase(market, pick);

    final String message;
    if (total <= 0) {
      message =
          'No one has called this yet. Back $outcome and you go first - your '
          'winnings grow as others back the other outcomes.';
    } else if (prob > 0.45) {
      message =
          '$pctText of the crowd is also on $outcome. A safer pick, but a '
          'smaller win.';
    } else {
      message =
          'Only $pctText of the crowd is on $outcome. Fewer people with you - '
          'if it wins, you take a bigger share of the pot.';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12.5.sp,
          height: 1.35,
          fontWeight: FontWeight.w500,
          color: AppColors.onPrimaryContainer,
        ),
      ),
    );
  }

  /// Quick-stake chips that fill the stake field. No MAX/balance chip: the
  /// arena's devnet USDC balance isn't surfaced on this screen and inventing
  /// one would be wrong.
  Widget _buildQuickStakeChips() {
    const options = [1, 2, 5];
    return Row(
      children: options.map((value) {
        final selected = _amount == value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: value == options.last ? 0 : 8.w),
            child: GestureDetector(
              onTap: () {
                _amountController.text = value.toString();
                _amountController.selection = TextSelection.collapsed(
                  offset: _amountController.text.length,
                );
                setState(() {});
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryContainer
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(11.r),
                  border: Border.all(
                    color: selected ? AppColors.primary : Colors.grey.shade300,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '$value USDC',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Live payout preview: recomputes as the stake and the selected outcome
  /// change, using the same parimutuel math as the web call screen.
  Widget _buildPayoutPreview(ArenaMarket market) {
    final pick = _selectedBucket;
    final stake = _amount;

    if (pick == null || stake <= 0) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Text(
          pick == null
              ? 'Pick an outcome and enter a stake to see your return.'
              : 'Enter a stake to see what you\'d win.',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final totalPool = _totalPool(market);
    final myBucketPool = _poolOf(market, pick);
    final losersPool = math.max(0.0, totalPool - myBucketPool);
    final newWinnersStake = myBucketPool + stake;
    final distributable = losersPool * (1 - _rakeBps / 10000);
    final profit =
        newWinnersStake > 0 ? (stake / newWinnersStake) * distributable : 0.0;
    final returnMult = stake > 0 ? (stake + profit) / stake : 1.0;
    final totalReturn = stake + profit;
    final hasUpside = losersPool > 0 && profit > 0;
    final ifWinsLabel = _ifOutcomeLabel(market, pick);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your return',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '≈ ${returnMult.toStringAsFixed(2)}×',
                    style: TextStyle(
                      fontSize: 26.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'You\'d get back',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    ArenaFormat.usdc(totalReturn),
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Divider(height: 1, color: Colors.grey.shade200),
          SizedBox(height: 12.h),
          _payoutRow(
            'Others backing other outcomes',
            ArenaFormat.usdc(losersPool),
          ),
          SizedBox(height: 8.h),
          _payoutRow(
            ifWinsLabel,
            hasUpside ? '+${ArenaFormat.usdc(profit)}' : 'Just your stake back',
            valueColor: hasUpside ? AppColors.primary : Colors.grey.shade600,
          ),
          SizedBox(height: 12.h),
          Text(
            hasUpside
                ? 'That\'s your stake back plus a share of the '
                    '${ArenaFormat.usdc(losersPool)} backing the other '
                    'outcomes (a 2.5% fee comes off). The more you stake, the '
                    'bigger your share, and your return grows as more people '
                    'back against you.'
                : 'You\'re first in on this outcome, so nothing is against you '
                    'yet. Your winnings come from people who back the other '
                    'outcomes - your return grows as others call.',
            style: TextStyle(
              fontSize: 11.5.sp,
              height: 1.4,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _payoutRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        SizedBox(width: 12.w),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountInput() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                // Digits and a single decimal point; any excess precision
                // beyond USDC's 6 decimals is simply rounded away when
                // converting to base units, so this only needs to keep the
                // field numeric - not fully validate structure.
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ),
          Text(
            'USDC',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final label =
        _amount > 0
            ? 'Place call • ${ArenaFormat.usdc(_amount)}'
            : 'Place call';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 16.h),
        ),
        child:
            _isSubmitting
                ? SizedBox(
                  height: 20.h,
                  width: 20.h,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                : Text(
                  label,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
      ),
    );
  }
}
