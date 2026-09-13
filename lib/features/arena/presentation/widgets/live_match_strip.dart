import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';

/// An honest, live match strip. Before kickoff it shows a countdown; while the
/// match is on it shows the REAL in-play score from the same TxLINE feed that
/// settles bets, updating on a poll; at full-time it shows the final score. It
/// invents nothing — no fake pitch, no fake motion. If the feed has no live
/// score yet, it just shows the countdown / a waiting line.
class LiveMatchStrip extends StatefulWidget {
  /// The fixture matchId (TxLINE fixture id), e.g. "18257739".
  final String matchId;
  final String home;
  final String away;
  final DateTime kickoff;

  const LiveMatchStrip({
    super.key,
    required this.matchId,
    required this.home,
    required this.away,
    required this.kickoff,
  });

  @override
  State<LiveMatchStrip> createState() => _LiveMatchStripState();
}

class _LiveMatchStripState extends State<LiveMatchStrip>
    with SingleTickerProviderStateMixin {
  ArenaLiveScore? _live;
  Timer? _poll;
  Timer? _clock;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fetch();
    // Poll the live score while the match could be on.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _fetch());
    // Local 1s tick so the pre-kickoff countdown stays live without polling.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _live == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final live = await context.read<ArenaProvider>().fetchLiveScore(
        widget.matchId,
      );
      if (!mounted) return;
      setState(() => _live = live);
      if (live?.finished == true) _poll?.cancel(); // nothing more will change
    } catch (_) {
      // Best-effort — a failed poll just leaves the last state in place.
    }
  }

  String _countdown(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return 'any moment';
  }

  @override
  Widget build(BuildContext context) {
    final live = _live;
    final now = DateTime.now();

    if (live != null) {
      return _scoreCard(finished: live.finished, home: live.home, away: live.away);
    }
    if (now.isBefore(widget.kickoff)) {
      return _infoCard(
        badge: 'KICKS OFF',
        badgeColor: AppColors.textSecondary,
        line1: 'in ${_countdown(widget.kickoff.difference(now))}',
        line2: 'The live score shows here the moment they kick off.',
      );
    }
    // Kicked off, but the feed hasn't published a scored snapshot yet.
    return _infoCard(
      badge: 'KICKED OFF',
      badgeColor: AppColors.primary,
      line1: '${widget.home} vs ${widget.away}',
      line2: 'Waiting for the live score from the feed…',
    );
  }

  Widget _shell({required Widget child, Color? border}) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
    decoration: BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(16.r),
      border: Border.all(color: border ?? const Color(0xFFEFE6E9), width: 1.5),
    ),
    child: child,
  );

  Widget _infoCard({
    required String badge,
    required Color badgeColor,
    required String line1,
    required String line2,
  }) {
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            badge,
            style: TextStyle(
              color: badgeColor,
              fontSize: 10.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            line1,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            line2,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5.sp),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard({
    required bool finished,
    required int home,
    required int away,
  }) {
    final accent = finished ? AppColors.textSecondary : AppColors.primary;
    return _shell(
      border: finished ? null : AppColors.primary.withValues(alpha: 0.35),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!finished) ...[
                FadeTransition(
                  opacity: _pulse,
                  child: Container(
                    width: 8.w,
                    height: 8.w,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                SizedBox(width: 6.w),
              ],
              Text(
                finished ? 'FULL-TIME' : 'LIVE · IN PLAY',
                style: TextStyle(
                  color: accent,
                  fontSize: 10.5.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.home,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                child: Text(
                  '$home - $away',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  widget.away,
                  textAlign: TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            finished
                ? 'Result verified on-chain via TxLINE.'
                : 'Live from the TxLINE feed. This is what settles your bet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5.sp),
          ),
        ],
      ),
    );
  }
}
