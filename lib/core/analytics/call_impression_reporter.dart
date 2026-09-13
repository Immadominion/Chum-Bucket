/// Impression counting for feed cards.
///
/// `feed_call_impression` is the denominator of the whole experiment: every
/// §9 go signal is "of the people who *saw* a card, how many did X". An
/// impression that fires twice for one card makes the people-first arm look
/// worse than it is, or better, depending on which arm happens to rebuild more.
/// So it is counted once per `(surface, callId)` per session, and the counting
/// is structural rather than a convention each screen has to remember:
///
/// * [CallImpressionTracker] builds the event through the typed constructor,
///   whose dedupe key is `(surface, callId)` with **no timestamp**, and hands
///   it to a recorder whose [AnalyticsDedupePolicy.oncePerSession] store
///   refuses the second one.
/// * [CallImpressionReporter] is the widget. It reports from a post-frame
///   callback in `initState` only, so a `setState`, a `Consumer` rebuild, a
///   parent relayout or a theme change cannot re-report. A `ListView` scrolling
///   a row out and back **does** recreate its `State` and report again — and
///   that second report is swallowed by the recorder, which is why the dedupe
///   lives there rather than in the widget.
///
/// The dedupe survives a rebuild because the recorder outlives the widget. It
/// resets on a viewer change (`AnalyticsRecorder.setUnit`) so a second account
/// is counted honestly.
library;

import 'package:flutter/widgets.dart';

import 'package:chumbucket/core/analytics/analytics_event.dart';
import 'package:chumbucket/core/analytics/analytics_events.dart';
import 'package:chumbucket/core/analytics/analytics_recorder.dart';

/// Builds and records impressions. Holds no state of its own — the dedupe
/// store is the recorder's, which is what makes it survive widget rebuilds.
class CallImpressionTracker {
  final AnalyticsRecorder _recorder;

  CallImpressionTracker({AnalyticsRecorder? recorder})
    : _recorder = recorder ?? AnalyticsRecorder.instance;

  AnalyticsRecorder get recorder => _recorder;

  /// Reports one card as seen. Returns true only when this was the first time
  /// this `(surface, callId)` was seen in this session.
  bool report({
    required String callId,
    required String marketId,
    required String authorId,
    required AnalyticsSurface surface,
    required int position,
    String? side,
    String? outcome,
    String? venue,
    bool? venueIsDemo,
    bool? thesisPresent,
    ThesisLengthBucket? thesisLengthBucket,
    bool? viewerIsSignedIn,
  }) {
    final outcomeOfRecord = _recorder.record(
      AnalyticsEvents.feedCallImpression(
        callId: callId,
        marketId: marketId,
        authorId: authorId,
        surface: surface,
        position: position,
        side: side,
        outcome: outcome,
        venue: venue,
        venueIsDemo: venueIsDemo,
        thesisPresent: thesisPresent,
        thesisLengthBucket: thesisLengthBucket,
        viewerIsSignedIn: viewerIsSignedIn,
      ),
    );
    return outcomeOfRecord == AnalyticsRecordOutcome.delivered;
  }
}

/// Wraps a call card and reports exactly one impression for it.
///
/// Drop it around the existing card; it adds no box, no padding and no paint —
/// it returns [child] unchanged.
class CallImpressionReporter extends StatefulWidget {
  final String callId;
  final String marketId;
  final String authorId;
  final AnalyticsSurface surface;
  final int position;

  final String? side;
  final String? outcome;
  final String? venue;
  final bool? venueIsDemo;
  final bool? thesisPresent;
  final ThesisLengthBucket? thesisLengthBucket;
  final bool? viewerIsSignedIn;

  /// Injected in tests; production leaves it null and uses the ambient one.
  final AnalyticsRecorder? recorder;

  final Widget child;

  const CallImpressionReporter({
    super.key,
    required this.callId,
    required this.marketId,
    required this.authorId,
    required this.surface,
    required this.position,
    required this.child,
    this.side,
    this.outcome,
    this.venue,
    this.venueIsDemo,
    this.thesisPresent,
    this.thesisLengthBucket,
    this.viewerIsSignedIn,
    this.recorder,
  });

  @override
  State<CallImpressionReporter> createState() => _CallImpressionReporterState();
}

class _CallImpressionReporterState extends State<CallImpressionReporter> {
  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(CallImpressionReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recycled element showing a different card is a different impression.
    // The same card re-entering here is not, and the recorder says so.
    if (oldWidget.callId != widget.callId ||
        oldWidget.surface != widget.surface) {
      _scheduleReport();
    }
  }

  void _scheduleReport() {
    // Post-frame: the row has been laid out, so this is "on screen" rather
    // than "constructed". Not re-armed on rebuild — see the library doc.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CallImpressionTracker(recorder: widget.recorder).report(
        callId: widget.callId,
        marketId: widget.marketId,
        authorId: widget.authorId,
        surface: widget.surface,
        position: widget.position,
        side: widget.side,
        outcome: widget.outcome,
        venue: widget.venue,
        venueIsDemo: widget.venueIsDemo,
        thesisPresent: widget.thesisPresent,
        thesisLengthBucket: widget.thesisLengthBucket,
        viewerIsSignedIn: widget.viewerIsSignedIn,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
