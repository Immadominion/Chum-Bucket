/// Analytics for the people-first vs market-first validation experiment.
///
/// ```dart
/// import 'package:chumbucket/core/analytics/analytics.dart';
/// ```
///
/// The shape of the package, in the order you meet it:
///
/// | File | What it is |
/// | --- | --- |
/// | `analytics_event.dart` | [AnalyticsEventName] — the roadmap's sixteen names, closed — plus the value type and the property keys. |
/// | `analytics_events.dart` | [AnalyticsEvents] — one typed constructor per name. The only way to build an event. |
/// | `analytics_privacy_guard.dart` | [AnalyticsPrivacyGuard] — the enforced control: no wallet, signature, balance, token, email or thesis text, ever. |
/// | `analytics_treatment.dart` | [TreatmentAssigner] — stable, storage-free 50/50 assignment to [FeedTreatment]. |
/// | `analytics_sink.dart` | [AnalyticsSink] and [InMemoryAnalyticsSink]. Nothing here touches the network. |
/// | `analytics_recorder.dart` | [AnalyticsRecorder] — stamps the arm, deduplicates, guards, delivers. |
/// | `call_impression_reporter.dart` | [CallImpressionReporter] — one impression per card per session. |
///
/// Two things this package deliberately does **not** do: it does not send
/// anything anywhere, and it does not compute a metric. It makes the seven-day
/// test measurable; reading the result is a separate, later job.
library;

export 'package:chumbucket/core/analytics/analytics_event.dart';
export 'package:chumbucket/core/analytics/analytics_events.dart';
export 'package:chumbucket/core/analytics/analytics_privacy_guard.dart';
export 'package:chumbucket/core/analytics/analytics_recorder.dart';
export 'package:chumbucket/core/analytics/analytics_sink.dart';
export 'package:chumbucket/core/analytics/analytics_treatment.dart';
export 'package:chumbucket/core/analytics/call_impression_reporter.dart';
export 'package:chumbucket/core/analytics/onboarding_analytics_events.dart';
