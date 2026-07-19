import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/data/match_arena_service.dart';
import 'package:chumbucket/features/arena/presentation/widgets/arena_format.dart';
import 'package:chumbucket/features/arena/presentation/widgets/live_match_strip.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

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
  bool _isFunding = false;
  String? _serviceError;

  /// Step copy shown next to the spinner while a bet is being submitted, so
  /// the two wallet prompts (place the bet, then post the pick) never read as
  /// a context-free freeze or a mystery second popup.
  String? _submitStatus;

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
      developer.log('DareYourselfScreen._ensureService failed: $e');
      if (mounted) {
        setState(
          () =>
              _serviceError =
                  'Couldn\'t reach your wallet just yet. Tap Retry.',
        );
      }
    }
  }

  /// Self-serve devnet faucet: fund the connected wallet with 100 test USDC of
  /// the program's PINNED mint. Needed because Circle's faucet hands out a
  /// different mint the program can't read, so those bets fail simulation. Play
  /// money on a practice network — nothing here is real. Does NOT touch the bet
  /// flow; it just tops up the wallet so a tester can actually place a bet.
  Future<void> _requestFaucet() async {
    final wallet = context.read<MwaAuthProvider>().walletAddress;
    if (wallet == null) {
      SnackBarUtils.showError(
        context,
        title: 'Connect your wallet first',
        subtitle: 'Log in with your wallet, then tap Get test USDC.',
      );
      return;
    }

    final arena = Provider.of<ArenaProvider>(context, listen: false);
    setState(() => _isFunding = true);
    try {
      final funded = await arena.requestFaucet(wallet);
      if (!mounted) return;
      if (funded) {
        SnackBarUtils.showSuccess(
          context,
          title: 'Test USDC added',
          subtitle: 'Added 100 test USDC — you can place a bet now.',
        );
      } else {
        SnackBarUtils.showSuccess(
          context,
          title: 'You\'re good to go',
          subtitle: 'You already have test USDC — you can place a bet now.',
        );
      }
    } catch (e) {
      developer.log('DareYourselfScreen._requestFaucet failed: $e');
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Couldn\'t add test USDC',
        subtitle: 'Something went wrong — please try again.',
      );
    } finally {
      if (mounted) setState(() => _isFunding = false);
    }
  }

  double get _amount => double.tryParse(_amountController.text.trim()) ?? 0;

  /// Whether this match can actually be bet on right now. Guards the whole
  /// form: no dead-end fillable UI for a match with no open market.
  bool _canBet(ArenaMarket? market) =>
      widget.match.isOpenForCalls &&
      market != null &&
      market.buckets.isNotEmpty &&
      market.status == 'OPEN';

  /// Turn a raw thrown error into one plain sentence a newcomer can act on.
  /// The raw string (e.g. "custom program error: 0x1771") stays in the logs.
  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('user rejected') ||
        raw.contains('declined') ||
        raw.contains('cancel') ||
        raw.contains('rejected')) {
      return 'You cancelled in your wallet — nothing was taken.';
    }
    if (raw.contains('insufficient') ||
        raw.contains('0x1') && raw.contains('funds') ||
        raw.contains('not enough')) {
      return 'Not enough USDC to cover this bet.';
    }
    if (raw.contains('locked') ||
        raw.contains('closed') ||
        raw.contains('started') ||
        raw.contains('kick')) {
      return 'This match already kicked off — bets are closed.';
    }
    if (raw.contains('blockhash') ||
        raw.contains('network') ||
        raw.contains('timeout') ||
        raw.contains('timed out') ||
        raw.contains('connection') ||
        raw.contains('socket')) {
      return 'Couldn\'t reach the network — please try again.';
    }
    return 'Something went wrong placing your bet — please try again.';
  }

  Future<void> _submit() async {
    final arena = Provider.of<ArenaProvider>(context, listen: false);
    final market = _selectedMarket;

    if (market == null || !_canBet(market)) {
      SnackBarUtils.showError(
        context,
        title: 'Betting isn\'t open',
        subtitle: 'Betting isn\'t open for this match yet.',
      );
      return;
    }
    if (_selectedBucket == null) {
      SnackBarUtils.showError(
        context,
        title: 'Pick an outcome',
        subtitle: 'Choose who you think wins before placing your bet.',
      );
      return;
    }
    if (_amount <= 0) {
      SnackBarUtils.showError(
        context,
        title: 'Enter an amount',
        subtitle: 'Enter how much you want to bet.',
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
          subtitle: _serviceError ?? 'Couldn\'t reach your wallet yet.',
        );
        return;
      }
    }

    final selectedTotal = market.bucketByIndex(_selectedBucket!);
    final displayLabel = _bucketLabel(market, _selectedBucket!);
    // The market's own bucket label ("HOME"/"OVER"/...) for the social layer.
    final bucketLabel = selectedTotal?.bucket ?? displayLabel;
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);

    setState(() {
      _isSubmitting = true;
      _submitStatus = 'Open your wallet and approve to place your bet…';
    });
    String? signature;
    try {
      signature = await arena.placeCall(
        match: widget.match,
        market: market,
        bucket: _selectedBucket!,
        bucketLabel: bucketLabel,
        amountUsdc: _amount,
        authProvider: authProvider,
      );
    } catch (e) {
      developer.log('DareYourselfScreen._submit placeCall failed: $e');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitStatus = null;
      });
      SnackBarUtils.showError(
        context,
        title: 'Couldn\'t place your bet',
        subtitle: _friendlyError(e),
      );
      return;
    }

    // The money is in. The second wallet prompt below only posts this pick to
    // the social feed (a message signature, not another payment) — done here,
    // inside the visible flow, with copy so it never surprises the user after
    // they leave. If it fails or they cancel it, the bet still stands.
    if (mounted) {
      setState(
        () => _submitStatus = 'One more quick approval to post your pick…',
      );
    }
    try {
      await arena.signAndRecordCallProof(
        authProvider: authProvider,
        match: widget.match,
        market: market,
        bucketLabel: bucketLabel,
        amountUsdc: _amount,
        txSignature: signature,
      );
    } catch (e) {
      developer.log('DareYourselfScreen._submit proof failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _submitStatus = null;
    });
    SnackBarUtils.showSuccess(
      context,
      title: 'Bet placed',
      subtitle: 'You\'ve bet ${ArenaFormat.usdc(_amount)} on $displayLabel.',
    );
    Navigator.pop(context, true);
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

    final canBet = _canBet(market);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Place your bet',
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
                SizedBox(height: 6.h),
                // M12: kickoff + the betting deadline, so the user knows how
                // long they have to get in.
                Text(
                  '${DateFormat('E, MMM d • h:mm a').format(widget.match.fixture.kickoff.toLocal())}  ·  Bets close at kickoff',
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
                SizedBox(height: 16.h),
                // Live, honest match state: countdown before kickoff, the real
                // in-play score while it's on (same feed that settles bets),
                // final score after. Only lights up when there's real data.
                LiveMatchStrip(
                  matchId: widget.match.fixture.matchId,
                  home: widget.match.fixture.home,
                  away: widget.match.fixture.away,
                  kickoff: widget.match.fixture.kickoff,
                ),
                SizedBox(height: 24.h),
                if (markets.length > 1) ...[
                  Text(
                    'What do you want to predict?',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildMarketSwitcher(markets, market),
                  SizedBox(height: 22.h),
                ],
                if (!canBet)
                  _buildClosedState()
                else ...[
                  Text(
                    market!.isLineMarket
                        ? 'What do you predict?'
                        : 'Pick who wins',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_marketSubtitle(market) != null) ...[
                    SizedBox(height: 4.h),
                    Text(
                      _marketSubtitle(market)!,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  SizedBox(height: 12.h),
                  _buildBucketPicker(market),
                  SizedBox(height: 12.h),
                  _buildPickInsight(market),
                  SizedBox(height: 28.h),
                  Text(
                    'Your bet',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildAmountInput(),
                  SizedBox(height: 8.h),
                  // M2: gloss USDC once, right by the amount field.
                  Text(
                    'USDC — digital US dollars, 1 USDC ≈ \$1',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildQuickStakeChips(),
                  SizedBox(height: 16.h),
                  _buildPayoutPreview(market),
                  SizedBox(height: 12.h),
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // H5: devnet / play-money disclosure at the moment of
                        // betting.
                        Text(
                          'This is play money on a practice network — nothing '
                          'here costs real cash.',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        // H8 + L6: plain "pool" language + where/when to claim.
                        Text(
                          'Your USDC moves into the shared pool, never into '
                          'anyone else\'s wallet. If your pick wins, you can '
                          'collect your winnings from My Bets once the match '
                          'finishes.',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        // M6: the refund-below-3 rule, always shown.
                        Text(
                          'If fewer than 3 people join this pool, everyone gets '
                          'their money back — you risk nothing.',
                          style: TextStyle(
                            fontSize: 11.5.sp,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildFaucetButton(),
                  if (_serviceError != null) ...[
                    SizedBox(height: 12.h),
                    _buildServiceErrorRetry(),
                  ],
                  if (_isSubmitting && _submitStatus != null) ...[
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            _submitStatus!,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 24.h),
                  _buildSubmitButton(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// H6: shown in place of the whole bet form when this match can't be bet on
  /// (no open market / already locked or settled). No dead-end fillable UI.
  Widget _buildClosedState() {
    // Accurate to WHY betting's closed: a live match has kicked off (watch the
    // score above), a finished one is over, otherwise it just hasn't opened.
    final message =
        widget.match.isLive
            ? 'This match has kicked off, so betting is closed. Follow the live score above.'
            : widget.match.status == 'RESOLVED'
            ? 'This match is over, so betting is closed.'
            : 'Betting isn\'t open for this match yet.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          BasilIcon('clock-outline', size: 22.sp, color: Colors.grey.shade600),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// H3: the wallet-not-ready body error, shown with a Retry that re-runs the
  /// service init instead of leaving the user stuck.
  Widget _buildServiceErrorRetry() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _serviceError!,
              style: TextStyle(color: AppColors.error, fontSize: 12.sp),
            ),
          ),
          TextButton(
            onPressed: _isSubmitting ? null : _ensureService,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Light segmented control to switch which bet type (Result / Total goals /
  /// Winning margin) you're on. Only shown when a fixture has more than one.
  Widget _buildMarketSwitcher(List<ArenaMarket> markets, ArenaMarket? current) {
    // A horizontally-scrollable row of pill tabs — sized to their text — so the
    // full book (Result + several goal/margin lines) stays readable however many
    // markets a fixture has, instead of being crushed into equal columns.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children:
            markets.map((m) {
              final selected = current?.marketId == m.marketId;
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: GestureDetector(
                  onTap: () => _selectMarket(m),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 9.h, horizontal: 14.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : AppColors.background,
                      borderRadius: BorderRadius.circular(999.r),
                      border:
                          selected
                              ? null
                              : Border.all(color: Colors.grey.shade300, width: 1),
                    ),
                    child: Text(
                      _marketTabLabel(m),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : Colors.grey.shade700,
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
    // Include the line so multiple goal/margin tabs stay distinct (e.g.
    // "Goals 1.5" vs "Goals 2.5"); the subtitle + bucket chips spell it out.
    final line = market.line?.line;
    final lineStr = line != null ? ' ${_trimLine(line)}' : '';
    switch (market.kind) {
      case 'RESULT':
        return 'Result';
      case 'OVER_UNDER':
        // H10: never show "O/U" jargon.
        return 'Goals$lineStr';
      case 'HANDICAP':
        // H10: never show "Handicap".
        return 'Margin$lineStr';
      default:
        return market.label;
    }
  }

  /// A one-line plain-English subtitle for the current bet type, so the tab
  /// name isn't the only explanation the user gets. Null for the Result type,
  /// which needs none.
  String? _marketSubtitle(ArenaMarket market) {
    switch (market.kind) {
      case 'OVER_UNDER':
        final line = market.line?.line;
        return line != null
            ? 'Over or under ${_trimLine(line)} goals in total'
            : 'Over or under the goals line';
      case 'HANDICAP':
        return 'Predict the winning margin';
      default:
        return null;
    }
  }

  /// "2.5" -> "2.5", "2.0" -> "2".
  String _trimLine(double value) =>
      value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toString();

  /// The chip label for one bucket. RESULT shows the real team names (or
  /// "Draw") — never HOME/DRAW/AWAY; line markets show the backend's plain
  /// label ("Over 2.5").
  String _bucketLabel(ArenaMarket market, int bucket) {
    if (!market.isLineMarket) {
      return ArenaFormat.outcomeNameFromIndex(
        bucket,
        home: widget.match.fixture.home,
        away: widget.match.fixture.away,
      );
    }
    return market.bucketByIndex(bucket)?.label ?? 'this pick';
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
                          selected ? AppColors.primary : Colors.grey.shade200,
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
                      // H7: never a bare number — say what it is.
                      Text(
                        'Backed',
                        style: TextStyle(
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Text(
                        ArenaFormat.usdcFromBaseUnits(total.stake),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '${ArenaFormat.percent(total.impliedProb)} of bets',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5.sp,
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
          'No one has bet on this yet. Back $outcome and you go first - your '
          'winnings grow as others bet on the other outcomes.';
    } else if (prob > 0.45) {
      message =
          '$pctText of the money so far is on $outcome. A safer pick, but a '
          'smaller win.';
    } else {
      message =
          'Only $pctText of the money so far is on $outcome. Fewer people with '
          'you - if it wins, you take a bigger share of the pool.';
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
                padding: EdgeInsets.symmetric(vertical: 12.h),
                alignment: Alignment.center,
                // Same grey.50 / grey.200 palette as the amount field above, so
                // the row reads as quick amounts for that field rather than a
                // strip of loose tags; selecting one highlights it like the
                // outcome picker.
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryContainer
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(
                    color: selected ? AppColors.primary : Colors.grey.shade200,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '$value USDC',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : Colors.black87,
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
              ? 'Pick an outcome and enter an amount to see what you\'d win.'
              : 'Enter an amount to see what you\'d win.',
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
              // H11: lead with the plain money amount as the hero; the
              // multiplier is the supporting line.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    'About',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '${returnMult.toStringAsFixed(2)}× your bet',
                    style: TextStyle(
                      fontSize: 15.sp,
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
            hasUpside ? '+${ArenaFormat.usdc(profit)}' : 'Just your bet back',
            valueColor: hasUpside ? AppColors.primary : Colors.grey.shade600,
          ),
          SizedBox(height: 12.h),
          Text(
            hasUpside
                ? 'That\'s your bet back plus a share of the '
                    '${ArenaFormat.usdc(losersPool)} bet on the other '
                    'outcomes (a 2.5% fee comes off). The more you bet, the '
                    'bigger your share, and your return grows as more people '
                    'bet against you.'
                : 'You\'re first in on this outcome, so nothing is against you '
                    'yet. Your winnings come from people who bet on the other '
                    'outcomes - your return grows as others bet.',
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
    // Matches the app's canonical amount field (see SendSolSheet): a grey.50
    // filled container with a 16.r radius and a thin resting border, holding a
    // borderless TextField plus a trailing currency affordance — instead of a
    // bespoke pill. Only the visual shell changed; the controller, keyboard
    // type, formatters and onChanged are byte-for-byte the same.
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.grey.shade200),
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
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.grey.shade400,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 16.h,
                ),
              ),
            ),
          ),
          // Tasteful currency affordance: a neutral tag echoing the SendSol
          // MAX-pill silhouette, kept grey so it never reads as tappable.
          Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'USDC',
                style: TextStyle(
                  fontSize: 12.5.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Secondary "Get test USDC" action: self-serve devnet faucet so a tester or
  /// judge can fund their own wallet with the program's PINNED test mint before
  /// betting. Deliberately outlined (not the pink gradient) so it never competes
  /// with the primary "Place bet" CTA below it.
  Widget _buildFaucetButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _isFunding ? null : _requestFaucet,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withAlpha(120), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 13.h),
        ),
        child:
            _isFunding
                ? SizedBox(
                  height: 18.h,
                  width: 18.h,
                  child: const CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    BasilIcon(
                      'wallet-outline',
                      size: 18.sp,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Get test USDC',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final label =
        _amount > 0
            ? 'Place bet • ${ArenaFormat.usdc(_amount)}'
            : 'Place bet';

    // Same gradient / radius / shadow / weight as the shared ChallengeButton
    // used on Home and Add-friend, so the primary CTA reads as the same app.
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(75),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 14.h),
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
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
      ),
    );
  }
}
