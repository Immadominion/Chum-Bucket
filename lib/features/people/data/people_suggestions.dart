/// `people.suggested`: people worth following, from real calls only
/// (onboarding spec §13.3). Public; the session (never an input) adds the
/// viewer's friends from the old app and removes the viewer and anyone they
/// already follow. Ordered by the public call record — never by money.
///
/// An optional capability, like [PeopleRepository]: a server that predates it
/// answers tRPC's NOT_FOUND, which surfaces here as
/// [PeopleSuggestionsUnavailable] so the caller can compose suggestions from
/// the reads that are deployed instead.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/people/data/people_models.dart';

/// Why someone is suggested. Never money.
enum SuggestionReason {
  ranked('ranked'),
  topCall('top_call'),
  building('building'),
  recent('recent'),
  friend('friend');

  const SuggestionReason(this.wire);
  final String wire;

  static SuggestionReason fromWire(Object? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    throw CallVocabularyException('Unknown suggestion reason "$v"');
  }
}

/// A person's latest live public call, as the server sends it.
class LatestLiveCall {
  const LatestLiveCall({
    required this.callId,
    required this.side,
    required this.marketId,
    required this.question,
    required this.closesAt,
  });

  final String callId;
  final Side side;
  final String marketId;
  final String question;
  final int? closesAt;

  static LatestLiveCall fromJson(Map<String, dynamic> json) => LatestLiveCall(
    callId: requireWireString(json['callId'], 'latestLiveCall.callId'),
    side: Side.fromWire(json['side']),
    marketId: requireWireString(json['marketId'], 'latestLiveCall.marketId'),
    question: requireWireString(json['question'], 'latestLiveCall.question'),
    closesAt:
        json['closesAt'] == null
            ? null
            : requireWireTimestampMs(json['closesAt'], 'latestLiveCall.closesAt'),
  );
}

class PersonSuggestion {
  const PersonSuggestion({
    required this.person,
    required this.reason,
    this.latestLiveCall,
  });

  final PersonCard person;
  final SuggestionReason reason;
  final LatestLiveCall? latestLiveCall;

  String get id => person.id;

  static PersonSuggestion fromJson(Map<String, dynamic> json) {
    final latest = optionalJsonMap(
      json['latestLiveCall'],
      'PersonSuggestion.latestLiveCall',
    );
    return PersonSuggestion(
      person: PersonCard.fromJson(json),
      reason: SuggestionReason.fromWire(json['reason']),
      latestLiveCall: latest == null ? null : LatestLiveCall.fromJson(latest),
    );
  }
}

class PeopleSuggestions {
  const PeopleSuggestions({
    required this.friends,
    required this.people,
    required this.servedAt,
  });

  /// The viewer's friends from the old app who are Chumbucket people. Empty
  /// when signed out.
  final List<PersonSuggestion> friends;

  /// People with at least one public free call, best evidence first.
  final List<PersonSuggestion> people;
  final int servedAt;

  static PeopleSuggestions fromJson(Map<String, dynamic> json) =>
      PeopleSuggestions(
        friends:
            requireJsonList(
              json['friends'],
              'people.suggested.friends',
            ).map(PersonSuggestion.fromJson).toList(),
        people:
            requireJsonList(
              json['people'],
              'people.suggested.people',
            ).map(PersonSuggestion.fromJson).toList(),
        servedAt: requireWireTimestampMs(
          json['servedAt'],
          'people.suggested.servedAt',
        ),
      );
}

/// The server does not have `people.suggested` yet.
class PeopleSuggestionsUnavailable implements Exception {
  const PeopleSuggestionsUnavailable();
}

abstract interface class PeopleSuggestionsRepository {
  Future<PeopleSuggestions> fetchSuggestedPeople({int limit = 10});
}
