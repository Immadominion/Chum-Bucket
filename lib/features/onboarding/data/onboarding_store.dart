/// Onboarding's per-install memory (onboarding spec §12), in
/// SharedPreferences. Every failure is swallowed: the worst case is the flow
/// starting again at Welcome for a signed-out person, or Home for a signed-in
/// one. Nothing here is a credential; the draft's reason never leaves the
/// phone and never reaches analytics.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';

/// `chumbucket_onboarding_v2`.
class OnboardingRecord {
  const OnboardingRecord({
    this.status = OnboardingStatus.fresh,
    this.stage,
    this.stageAt,
    this.startedAt,
    this.completedAt,
    this.homeCardShows = 0,
    this.homeCardDeclines = 0,
    this.upgradeIntroSeen = false,
    this.handleClaimDeferred = false,
    this.forYouPending = false,
    this.setupSkipped = false,
    this.homeCardDone = false,
  });

  final OnboardingStatus status;

  /// The step a run was on, for resuming after process death (§3 row 3).
  final String? stage;
  final int? stageAt;
  final int? startedAt;
  final int? completedAt;

  /// How many sessions showed Home's "Make Home yours" card, and how many
  /// times it was put off.
  final int homeCardShows;
  final int homeCardDeclines;
  final bool upgradeIntroSeen;

  /// "Later" on "Pick your @username" (A2c) on this install.
  final bool handleClaimDeferred;

  /// Topics were chosen and Markets has not opened on "For you" yet.
  final bool forYouPending;

  /// Topics and people were both offered and both skipped.
  final bool setupSkipped;

  /// "Make Home yours" was completed; the card never shows again.
  final bool homeCardDone;

  DateTime? get stageAtUtc =>
      stageAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(stageAt!, isUtc: true);

  OnboardingRecord copyWith({
    OnboardingStatus? status,
    String? stage,
    bool clearStage = false,
    int? stageAt,
    int? startedAt,
    int? completedAt,
    int? homeCardShows,
    int? homeCardDeclines,
    bool? upgradeIntroSeen,
    bool? handleClaimDeferred,
    bool? forYouPending,
    bool? setupSkipped,
    bool? homeCardDone,
  }) => OnboardingRecord(
    status: status ?? this.status,
    stage: clearStage ? null : (stage ?? this.stage),
    stageAt: clearStage ? null : (stageAt ?? this.stageAt),
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt ?? this.completedAt,
    homeCardShows: homeCardShows ?? this.homeCardShows,
    homeCardDeclines: homeCardDeclines ?? this.homeCardDeclines,
    upgradeIntroSeen: upgradeIntroSeen ?? this.upgradeIntroSeen,
    handleClaimDeferred: handleClaimDeferred ?? this.handleClaimDeferred,
    forYouPending: forYouPending ?? this.forYouPending,
    setupSkipped: setupSkipped ?? this.setupSkipped,
    homeCardDone: homeCardDone ?? this.homeCardDone,
  );

  Map<String, Object?> toJson() => {
    'v': 2,
    'status': status.wire,
    'stage': stage,
    'stageAt': stageAt,
    'startedAt': startedAt,
    'completedAt': completedAt,
    'homeCardShows': homeCardShows,
    'homeCardDeclines': homeCardDeclines,
    'upgradeIntroSeen': upgradeIntroSeen,
    'handleClaimDeferred': handleClaimDeferred,
    'forYouPending': forYouPending,
    'setupSkipped': setupSkipped,
    'homeCardDone': homeCardDone,
  };

  static OnboardingRecord fromJson(Map<String, dynamic> json) {
    int? i(Object? v) => v is int ? v : null;
    return OnboardingRecord(
      status: OnboardingStatus.fromWire(json['status']),
      stage: json['stage'] is String ? json['stage'] as String : null,
      stageAt: i(json['stageAt']),
      startedAt: i(json['startedAt']),
      completedAt: i(json['completedAt']),
      homeCardShows: i(json['homeCardShows']) ?? 0,
      homeCardDeclines: i(json['homeCardDeclines']) ?? 0,
      upgradeIntroSeen: json['upgradeIntroSeen'] == true,
      handleClaimDeferred: json['handleClaimDeferred'] == true,
      forYouPending: json['forYouPending'] == true,
      setupSkipped: json['setupSkipped'] == true,
      homeCardDone: json['homeCardDone'] == true,
    );
  }
}

/// `chumbucket_pending_follows_v1`: people chosen while signed out.
class PendingFollows {
  const PendingFollows(this.ids, this.savedAt);
  final List<String> ids;
  final int savedAt;

  static const Duration lifetime = Duration(days: 7);

  bool isLiveAt(DateTime now) =>
      ids.isNotEmpty &&
      now.toUtc().millisecondsSinceEpoch - savedAt <= lifetime.inMilliseconds;

  Map<String, Object?> toJson() => {'ids': ids, 'savedAt': savedAt};

  static PendingFollows? fromJson(Map<String, dynamic> json) {
    final ids = json['ids'];
    final savedAt = json['savedAt'];
    if (ids is! List || savedAt is! int) return null;
    return PendingFollows([
      for (final id in ids)
        if (id is String && id.isNotEmpty) id,
    ], savedAt);
  }
}

/// What a draft was going to become.
enum PendingCallKind {
  call('call'),
  back('back'),
  fade('fade');

  const PendingCallKind(this.wire);
  final String wire;

  static PendingCallKind? fromWire(Object? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null;
  }
}

/// `chumbucket_pending_call_v1`: a call composed while signed out. It is
/// reopened for a fresh Lock after sign-in — never locked on its own,
/// because the price stamp may have changed and calls can't be edited.
class PendingCall {
  const PendingCall({
    required this.kind,
    required this.marketId,
    required this.side,
    required this.savedAt,
    this.thesis,
    this.visibility = CallVisibility.public,
    this.confidence,
    this.targetCallId,
    this.question,
  });

  final PendingCallKind kind;
  final String marketId;
  final Side side;
  final String? thesis;
  final CallVisibility visibility;
  final double? confidence;

  /// The call a Back/Fade answers.
  final String? targetCallId;

  /// The market's question, for the draft card on the sign-in screen. Shown
  /// on this phone only.
  final String? question;
  final int savedAt;

  static const Duration lifetime = Duration(hours: 24);

  bool isLiveAt(DateTime now) =>
      now.toUtc().millisecondsSinceEpoch - savedAt <= lifetime.inMilliseconds;

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'marketId': marketId,
    'side': side.wire,
    'thesis': thesis,
    'visibility': visibility.wire,
    'confidence': confidence,
    'targetCallId': targetCallId,
    'question': question,
    'savedAt': savedAt,
  };

  static PendingCall? fromJson(Map<String, dynamic> json) {
    final kind = PendingCallKind.fromWire(json['kind']);
    final marketId = json['marketId'];
    final savedAt = json['savedAt'];
    if (kind == null || marketId is! String || savedAt is! int) return null;
    Side side;
    CallVisibility visibility;
    try {
      side = Side.fromWire(json['side']);
      visibility =
          json['visibility'] == null
              ? CallVisibility.public
              : CallVisibility.fromWire(json['visibility']);
    } on CallVocabularyException {
      return null;
    }
    final confidence = json['confidence'];
    if ((kind == PendingCallKind.back || kind == PendingCallKind.fade) &&
        json['targetCallId'] is! String) {
      return null;
    }
    return PendingCall(
      kind: kind,
      marketId: marketId,
      side: side,
      savedAt: savedAt,
      thesis: json['thesis'] is String ? json['thesis'] as String : null,
      visibility: visibility,
      confidence: confidence is num ? confidence.toDouble() : null,
      targetCallId:
          json['targetCallId'] is String
              ? json['targetCallId'] as String
              : null,
      question: json['question'] is String ? json['question'] as String : null,
    );
  }
}

class OnboardingStore {
  const OnboardingStore();

  static const recordKey = 'chumbucket_onboarding_v2';
  static const topicsKey = 'chumbucket_topics_v1';
  static const pendingFollowsKey = 'chumbucket_pending_follows_v1';
  static const pendingCallKey = 'chumbucket_pending_call_v1';

  /// The old carousel's bool. Read only, as a hint that this install ran the
  /// old app; v2 never writes it.
  static const legacyCompletedKey = 'onboardingCompleted';

  Future<Map<String, dynamic>?> _readJson(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeJson(String key, Map<String, Object?>? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(value));
      }
    } catch (_) {
      // Never blocks a step.
    }
  }

  Future<OnboardingRecord> readRecord() async {
    final json = await _readJson(recordKey);
    return json == null
        ? const OnboardingRecord()
        : OnboardingRecord.fromJson(json);
  }

  Future<void> writeRecord(OnboardingRecord record) =>
      _writeJson(recordKey, record.toJson());

  Future<bool> legacyOnboardingCompleted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(
            legacyCompletedKey,
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// Chosen topics, as category slugs. Kept across sign-out: it is a device
  /// preference, like a filter.
  Future<List<String>> readTopics() async {
    try {
      final list = (await SharedPreferences.getInstance()).getStringList(
        topicsKey,
      );
      return list ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeTopics(List<String> topics) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(
        topicsKey,
        topics,
      );
    } catch (_) {}
  }

  Future<PendingFollows?> readPendingFollows(DateTime now) async {
    final json = await _readJson(pendingFollowsKey);
    final follows = json == null ? null : PendingFollows.fromJson(json);
    if (follows == null || !follows.isLiveAt(now)) {
      if (json != null) await _writeJson(pendingFollowsKey, null);
      return null;
    }
    return follows;
  }

  Future<void> writePendingFollows(PendingFollows? follows) => _writeJson(
    pendingFollowsKey,
    follows == null || follows.ids.isEmpty ? null : follows.toJson(),
  );

  Future<PendingCall?> readPendingCall(DateTime now) async {
    final json = await _readJson(pendingCallKey);
    final call = json == null ? null : PendingCall.fromJson(json);
    if (call == null || !call.isLiveAt(now)) {
      if (json != null) await _writeJson(pendingCallKey, null);
      return null;
    }
    return call;
  }

  Future<void> writePendingCall(PendingCall? call) =>
      _writeJson(pendingCallKey, call?.toJson());

  /// Sign-out forgets what was waiting on the account (pending follows and
  /// the draft call). Topics and the onboarding status stay: they belong to
  /// the phone.
  Future<void> clearForSignOut() async {
    await _writeJson(pendingFollowsKey, null);
    await _writeJson(pendingCallKey, null);
  }
}
