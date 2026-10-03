/// `people.find`: who an X handle, a Chumbucket @username or a wallet belongs
/// to — the confirmation card shown before adding a friend.
///
/// Adding a friend is following a real Chumbucket person. Nothing is written
/// by a lookup, and no wallet signature is involved: the add itself is
/// `people.follow`, keyed by the signed-in session, once the person has seen
/// the card.
///
/// An optional capability, like `PeopleSuggestionsRepository`: a server that
/// predates `people.find` answers tRPC's NOT_FOUND, which surfaces here as
/// [PersonFinderUnavailable].
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/profile/data/avatar_catalog.dart';

/// What the query was taken as.
enum PersonLookupKind {
  /// An X profile link: X accounts only.
  x('x'),

  /// `@name` or `name`: an X account and a Chumbucket @username.
  handle('handle'),
  wallet('wallet');

  const PersonLookupKind(this.wire);
  final String wire;

  static PersonLookupKind fromWire(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse:
        () =>
            throw CallVocabularyException(
              'Unknown person lookup kind "$value"',
            ),
  );
}

/// How a match was found.
enum PersonMatchedBy {
  /// They signed in to Chumbucket with that X account.
  x('x'),
  username('username'),
  wallet('wallet');

  const PersonMatchedBy(this.wire);
  final String wire;

  static PersonMatchedBy fromWire(Object? value) => values.firstWhere(
    (kind) => kind.wire == value,
    orElse:
        () => throw CallVocabularyException('Unknown person match "$value"'),
  );
}

/// An https picture, or null. Anything else on the wire is ignored, never
/// rendered.
String? _httpsOrNull(Object? value) =>
    value is String && value.startsWith('https://') ? value : null;

/// An X username without its @, or null.
String? _xHandleOrNull(Object? value) {
  if (value is! String) return null;
  final handle = value.trim().replaceFirst(RegExp(r'^@'), '');
  return RegExp(r'^[A-Za-z0-9_]{1,15}$').hasMatch(handle) ? handle : null;
}

class PersonMatch {
  const PersonMatch({
    required this.person,
    required this.matchedBy,
    this.xHandle,
    this.xAvatarUrl,
    this.avatarArt,
    this.isViewer = false,
  });

  /// Their card, with the same public record `people.get` shows.
  final PersonCard person;
  final PersonMatchedBy matchedBy;

  /// Their X username (no @), when they signed in with X.
  final String? xHandle;

  /// Their X profile picture from that sign-in.
  final String? xAvatarUrl;

  /// The avatar they chose in the app (1..5), as an asset.
  final String? avatarArt;

  /// The signed-in person themselves.
  final bool isViewer;

  bool get isFollowing => person.viewerIsFollowing;

  /// Their real pictures, best first: the X photo, their own picture, the
  /// avatar they chose. A card shows the first that loads, then initials.
  List<String> get pictures => {
    if (xAvatarUrl != null) xAvatarUrl!,
    if (person.avatarUrl != null) person.avatarUrl!,
    if (avatarArt != null) avatarArt!,
  }.toList(growable: false);

  PersonMatch copyWith({bool? viewerIsFollowing}) => PersonMatch(
    person: PersonCard(
      id: person.id,
      handle: person.handle,
      displayName: person.displayName,
      avatarUrl: person.avatarUrl,
      record: person.record,
      viewerIsFollowing: viewerIsFollowing ?? person.viewerIsFollowing,
    ),
    matchedBy: matchedBy,
    xHandle: xHandle,
    xAvatarUrl: xAvatarUrl,
    avatarArt: avatarArt,
    isViewer: isViewer,
  );

  factory PersonMatch.fromJson(Map<String, dynamic> json) {
    final person = requireJsonMap(json['person'], 'PersonMatch.person');
    return PersonMatch(
      person: PersonCard.fromJson(person),
      matchedBy: PersonMatchedBy.fromWire(json['matchedBy']),
      xHandle: _xHandleOrNull(json['xHandle']),
      xAvatarUrl: _httpsOrNull(json['xAvatarUrl']),
      avatarArt: avatarAssetFor(person['avatarId']),
      isViewer: requireWireBool(json['isViewer'], 'PersonMatch.isViewer'),
    );
  }
}

/// An X handle with no Chumbucket account behind it.
class NotOnChumbucket {
  const NotOnChumbucket({required this.xHandle, this.xAvatarUrl});

  /// Without @.
  final String xHandle;

  /// Their public X profile picture, when the server found one.
  final String? xAvatarUrl;

  static NotOnChumbucket? fromJson(Object? value) {
    final json = optionalJsonMap(value, 'people.find.notOnChumbucket');
    if (json == null) return null;
    final handle = _xHandleOrNull(json['xHandle']);
    if (handle == null) {
      throw const CallVocabularyException(
        'notOnChumbucket.xHandle must be an X handle',
      );
    }
    return NotOnChumbucket(
      xHandle: handle,
      xAvatarUrl: _httpsOrNull(json['xAvatarUrl']),
    );
  }
}

class PersonLookup {
  const PersonLookup({
    required this.kind,
    required this.matches,
    this.handle,
    this.notOnChumbucket,
  });

  final PersonLookupKind kind;

  /// The handle looked up (lowercase, no @); null for a wallet.
  final String? handle;

  /// Most likely first. Empty when nobody matched.
  final List<PersonMatch> matches;

  /// Set only when nobody matched and the query can be an X handle.
  final NotOnChumbucket? notOnChumbucket;

  bool get isEmpty => matches.isEmpty;

  factory PersonLookup.fromJson(Map<String, dynamic> json) => PersonLookup(
    kind: PersonLookupKind.fromWire(json['kind']),
    handle: json['handle'] is String ? json['handle'] as String : null,
    matches: requireJsonList(
      json['matches'],
      'people.find.matches',
    ).map(PersonMatch.fromJson).toList(growable: false),
    notOnChumbucket: NotOnChumbucket.fromJson(json['notOnChumbucket']),
  );
}

/// The server does not have `people.find` yet.
class PersonFinderUnavailable implements Exception {
  const PersonFinderUnavailable();
}

abstract interface class PersonFinderRepository {
  /// Session only. Throws the signed-out exception without one, and
  /// [PersonFinderUnavailable] on a server that predates the lookup.
  Future<PersonLookup> findPerson(String query);
}
