/// W1's phone: a live, tappable preview of Chumbucket inside a phone drawn
/// in perspective (looking down at it, so the top reads wider than the
/// bottom), fading into the page. Everything inside is real: calls from
/// production or markets open on Panta, with Panta's prices. Nothing here is
/// a fixture; while data loads the screen shows quiet skeleton rows.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_format.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

/// The phone, its perspective and its fade. [strip] null means still loading.
class WelcomePhone extends StatelessWidget {
  const WelcomePhone({
    super.key,
    required this.feed,
    required this.now,
    required this.onOpenCall,
    required this.onOpenMarket,
    this.offline = false,
    this.clearBottom = 0,
  });

  /// Offline: the phone says so instead of waiting.
  final bool offline;

  /// The bottom band (dp) that must be fully transparent: content drawn
  /// over the stage there (W1's headline) never sits on the phone.
  final double clearBottom;

  final WelcomeFeed? feed;
  final DateTime now;
  final void Function(CallFeedEntry entry) onOpenCall;
  final void Function(VenueMarket market) onOpenMarket;

  /// Tilt of the phone's top towards the viewer, in radians.
  static const double tilt = 0.40;

  @override
  Widget build(BuildContext context) {
    final still = !onbAmbient(context);
    // A miniature of the app, drawn at a fixed card size: its text does not
    // grow with the system text size (large text would only clip it). Each
    // card is still one labelled button, and opens the full, scalable view.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.min(box.maxWidth * 0.74, 340.0);
          // Taller than the stage: the phone runs past the bottom and dissolves
          // there, so no bottom edge ever shows.
          final height = math.max(width * 2.18, box.maxHeight * 1.35);
          final people = _people(feed);
          return ShaderMask(
            // The phone dissolves into the page instead of ending on an edge.
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final end =
                  rect.height <= 0
                      ? 1.0
                      : (1 - (clearBottom + 12) / rect.height).clamp(.4, 1.0);
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Colors.white, Colors.white, Colors.transparent],
                stops: [0, (end - .36).clamp(0.0, end), end],
              ).createShader(rect);
            },
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: _PeekHint(
                  enabled: !still,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Transform(
                      alignment: Alignment.topCenter,
                      transform:
                          Matrix4.identity()
                            ..setEntry(3, 2, 0.0013)
                            ..rotateX(tilt),
                      child: SizedBox(
                        width: width + 72,
                        height: height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 36,
                              top: 0,
                              width: width,
                              height: height,
                              child: _PhoneFrame(
                                child: _PreviewFeed(
                                  feed: feed,
                                  offline: offline,
                                  now: now,
                                  animate: !still,
                                  onOpenCall: onOpenCall,
                                  onOpenMarket: onOpenMarket,
                                ),
                              ),
                            ),
                            for (var i = 0; i < people.length; i++)
                              _FloatingPerson(
                                person: people[i].$1,
                                side: people[i].$2,
                                index: i,
                                animate: !still,
                                left: 36 + width - 30 - (i.isOdd ? 22 : 0),
                                top: 120.0 + i * 78,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Distinct real people behind the live calls, with the side they took.
  static List<(Person, Side)> _people(WelcomeFeed? feed) {
    final seen = <String>{};
    return [
      for (final item in feed?.items ?? const <LiveItem>[])
        if (item is LiveCallItem && seen.add(item.entry.author.id))
          (item.entry.author, item.entry.call.side),
    ].take(4).toList();
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF15161A),
      borderRadius: BorderRadius.circular(48),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33111827),
          blurRadius: 40,
          offset: Offset(0, 18),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(9),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: ColoredBox(
          color: AppColors.background,
          child: Stack(
            children: [
              Positioned.fill(child: child),
              // The island, drawn over the content like the real thing.
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 92,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFF15161A),
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The feed inside the phone. Advances one card at a time on its own and
/// pauses for a while when touched; reduced motion keeps it still.
class _PreviewFeed extends StatefulWidget {
  const _PreviewFeed({
    required this.feed,
    required this.offline,
    required this.now,
    required this.animate,
    required this.onOpenCall,
    required this.onOpenMarket,
  });

  final WelcomeFeed? feed;
  final bool offline;
  final DateTime now;
  final bool animate;
  final void Function(CallFeedEntry entry) onOpenCall;
  final void Function(VenueMarket market) onOpenMarket;

  @override
  State<_PreviewFeed> createState() => _PreviewFeedState();
}

class _PreviewFeedState extends State<_PreviewFeed> {
  static const double _extent = 112;
  final _scroll = ScrollController();
  Timer? _tick;
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final _pricesAsked = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _tick = Timer.periodic(
        const Duration(milliseconds: 3200),
        (_) => _step(),
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _step() {
    final items = widget.feed?.items ?? const <LiveItem>[];
    if (!widget.animate || items.length < 2 || !_scroll.hasClients) return;
    if (DateTime.now().isBefore(_pausedUntil)) return;
    final next = ((_scroll.offset / _extent).round() + 1) * _extent;
    _scroll.animateTo(
      next,
      duration: const Duration(milliseconds: 820),
      curve: Curves.easeInOutCubic,
    );
  }

  void _askPrices(List<LiveItem> items) {
    final calls = context.read<CallsProvider>();
    for (final item in items) {
      if (item is LiveMarketItem && _pricesAsked.add(item.market.id)) {
        unawaited(calls.loadMarketDetail(item.market.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.feed?.items;
    final loading = items == null && !widget.offline;
    if (items != null && items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askPrices(items);
      });
    }
    final markets = widget.feed != null && !widget.feed!.hasCalls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 50),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const _LiveDot(),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  markets ? 'Open on Panta' : 'On Chumbucket',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'PPNeueMachina',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child:
              loading
                  ? const _SkeletonCards(extent: _extent)
                  : items == null || items.isEmpty
                  ? _PhoneEmpty(offline: widget.offline)
                  : NotificationListener<ScrollStartNotification>(
                    onNotification: (n) {
                      if (n.dragDetails != null) {
                        _pausedUntil = DateTime.now().add(
                          const Duration(seconds: 8),
                        );
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemExtent: _extent,
                      // One card loops into the next forever; a single item
                      // stays a single, still card.
                      itemCount: items.length < 2 ? items.length : null,
                      itemBuilder: (context, i) {
                        final item = items[i % items.length];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: switch (item) {
                            LiveCallItem(:final entry) => _MiniCallCard(
                              entry: entry,
                              onTap: () => widget.onOpenCall(entry),
                            ),
                            LiveMarketItem(:final market) => _MiniMarketCard(
                              market: market,
                              now: widget.now,
                              onTap: () => widget.onOpenMarket(market),
                            ),
                          },
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.child, required this.onTap, this.label});
  final Widget child;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          child: child,
        ),
      ),
    ),
  );
}

const _question = TextStyle(
  fontFamily: 'PPNeueMachina',
  fontSize: 12.5,
  fontWeight: FontWeight.w800,
  height: 1.3,
  color: AppColors.textPrimary,
);

bool _settled(CallFeedEntry e) =>
    e.result != null && e.result!.outcome != CallOutcome.pending;

class _MiniCallCard extends StatelessWidget {
  const _MiniCallCard({required this.entry, required this.onTap});
  final CallFeedEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final author = entry.author;
    final price = OnbFormat.lockedPrice(entry.call);
    final free = !entry.isFunded && entry.call.fundingState.isFree;
    final facts = [
      if (price != null) '${entry.call.side.wire} · $price',
      if (_settled(entry)) entry.result!.outcome.label,
    ].join(' · ');
    return _MiniCard(
      onTap: onTap,
      label:
          '${author.displayName} called ${entry.call.side.wire} on '
          '${entry.market.question}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                imageUrl: author.avatarUrl,
                initials: author.initials,
                size: 22,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  author.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SidePill(side: entry.call.side),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              entry.market.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _question,
            ),
          ),
          if (facts.isNotEmpty || free)
            Row(
              children: [
                Expanded(
                  child: Text(
                    facts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (free) const FreeMarker(),
              ],
            ),
        ],
      ),
    );
  }
}

class _MiniMarketCard extends StatelessWidget {
  const _MiniMarketCard({
    required this.market,
    required this.now,
    required this.onTap,
  });
  final VenueMarket market;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = context.select<CallsProvider, SharePriceSnapshot?>(
      (c) => c.marketDetail(market.id)?.sharePrice,
    );
    return _MiniCard(
      onTap: onTap,
      label: market.question,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  market.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _question,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _PriceCell(
                  side: Side.yes,
                  value: CallsFormat.sideOdds(price, Side.yes),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _PriceCell(
                  side: Side.no,
                  value: CallsFormat.sideOdds(price, Side.no),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({required this.side, required this.value});
  final Side side;
  /// The side's odds, already a percent ("59%"), or null.
  final String? value;

  @override
  Widget build(BuildContext context) {
    final yes = side == Side.yes;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: yes ? const Color(0xFFE6F6EF) : const Color(0xFFEEF0F4),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              side.wire,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: yes ? const Color(0xFF07644C) : const Color(0xFF334155),
              ),
            ),
          ),
          Text(
            value ?? '—',
            style: TextStyle(
              fontFamily: 'PPNeueMachina',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: yes ? const Color(0xFF07644C) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCards extends StatelessWidget {
  const _SkeletonCards({required this.extent});
  final double extent;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: extent - 10,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    ),
  );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!onbAmbient(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    height: 10,
    child: AnimatedBuilder(
      animation: _pulse,
      builder:
          (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 6 + 6 * _pulse.value,
                height: 6 + 6 * _pulse.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(
                    0xFF10B981,
                  ).withValues(alpha: .35 * (1 - _pulse.value)),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
    ),
  );
}

/// A real caller floating off the phone's edge, with the side they took.
class _FloatingPerson extends StatefulWidget {
  const _FloatingPerson({
    required this.person,
    required this.side,
    required this.index,
    required this.animate,
    required this.left,
    required this.top,
  });

  final Person person;
  final Side side;
  final int index;
  final bool animate;
  final double left;
  final double top;

  @override
  State<_FloatingPerson> createState() => _FloatingPersonState();
}

class _FloatingPersonState extends State<_FloatingPerson>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 2600 + widget.index * 420),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _bob.repeat(reverse: true);
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.index == 0 ? 64.0 : 54.0;
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: AnimatedBuilder(
        animation: _bob,
        builder:
            (context, child) => Transform.translate(
              offset: Offset(0, -5 * Curves.easeInOut.transform(_bob.value)),
              child: child,
            ),
        child: Semantics(
          label: '${widget.person.displayName} called ${widget.side.wire}',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x26111827),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: AppAvatar(
                  imageUrl: widget.person.avatarUrl,
                  initials: widget.person.initials,
                  size: size,
                ),
              ),
              Positioned(
                right: -4,
                bottom: -2,
                child: SidePill(side: widget.side),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A game-style affordance: the phone lifts as if dragged up, then settles
/// back, so it reads as something you can touch. Once shortly after it
/// appears, then every few seconds until the first touch; never under
/// reduced motion.
class _PeekHint extends StatefulWidget {
  const _PeekHint({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  State<_PeekHint> createState() => _PeekHintState();
}

class _PeekHintState extends State<_PeekHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final Animation<double> _lift = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: -34.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
    TweenSequenceItem(tween: ConstantTween(-34.0), weight: 8),
    TweenSequenceItem(
      tween: Tween(
        begin: -34.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 62,
    ),
  ]).animate(_c);
  Timer? _timer;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _timer = Timer(const Duration(milliseconds: 1500), _peek);
    }
  }

  void _peek() {
    if (!mounted || _touched) return;
    _c.forward(from: 0);
    _timer = Timer(const Duration(seconds: 6), _peek);
  }

  void _stop() {
    _touched = true;
    _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _stop(),
    child: AnimatedBuilder(
      animation: _lift,
      builder:
          (context, child) =>
              Transform.translate(offset: Offset(0, _lift.value), child: child),
      child: widget.child,
    ),
  );
}

/// The phone with nothing real to show yet (offline, or the API down): says
/// so plainly. The screen keeps asking in the background.
class _PhoneEmpty extends StatelessWidget {
  const _PhoneEmpty({required this.offline});
  final bool offline;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(
      children: [
        const ChumbucketStateArt(ChumbucketStateArtwork.calls, size: 132),
        const SizedBox(height: 14),
        Text(
          offline
              ? OnboardingCopy.welcomePhoneOffline
              : OnboardingCopy.welcomePhoneEmpty,
          key: const ValueKey('welcome-phone-empty'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
