/// The people layer, as an optional capability of a calls repository.
///
/// Optional on purpose, exactly as `CallsCatalogRepository` is: the seeded
/// mock repository does not implement it, so a demo build shows these
/// surfaces as unavailable rather than inventing rankings, top calls or
/// threads. Only the live BFF repository implements it.
///
/// No method takes a viewer id. The server derives the viewer from the session
/// token, so a client cannot read someone else's following list or unlock a
/// crowd split by naming a stranger.
library;

import 'package:chumbucket/features/people/data/people_models.dart';

abstract interface class PeopleRepository {
  /// People ranked by their public call record inside [window].
  Future<Leaderboard> fetchLeaderboard({
    required LeaderboardWindow window,
    int limit = 50,
  });

  /// The directory by handle or name. Never by wallet.
  Future<List<PersonCard>> searchPeople(String query, {int limit = 20});

  /// The signed-in person's own follow list. Throws the signed-out exception
  /// when there is no session.
  Future<List<PersonCard>> fetchFollowing();

  /// Open calls worth answering, for Home.
  Future<List<TopCall>> fetchTopCalls({int limit = 10});

  /// Append a timestamped update to the signed-in person's own call.
  Future<ThesisUpdate> appendThesisUpdate({
    required String callId,
    required String body,
  });
}
