/// Copy for a person's record. Display only, and never more confident than
/// the record: a percentage appears only when the server sent one, and every
/// form names its denominator.
library;

import 'package:intl/intl.dart';

import 'package:chumbucket/features/people/data/people_models.dart';

class PeopleFormat {
  PeopleFormat._();

  static final DateFormat _joined = DateFormat('MMM yyyy');

  /// "94%", or null when the record has not earned a percentage.
  static String? accuracy(PublicRecord record) =>
      record.accuracy == null ? null : '${(record.accuracy! * 100).round()}%';

  /// One line for a list row: "94% · 47/50 decided", "4/4 correct",
  /// "2 awaiting result", "No public calls yet".
  static String recordShort(PublicRecord record) {
    final percent = accuracy(record);
    if (percent != null) {
      return '$percent · ${record.correct}/${record.decided} decided';
    }
    if (record.decided > 0) {
      return '${record.correct}/${record.decided} correct';
    }
    if (record.pending > 0) return '${record.pending} awaiting result';
    return 'No public calls yet';
  }

  /// What is still missing before a percentage or a rank: "6 more decided
  /// calls to rank". Null once there is nothing missing.
  static String? toRank(PublicRecord record) {
    final missing = record.decidedToRank;
    if (missing == 0) return null;
    return '$missing more decided call${missing == 1 ? '' : 's'} to rank';
  }

  /// "Joined Mar 2026", or null when the join date is unknown.
  static String? joined(DateTime? joinedAtUtc) =>
      joinedAtUtc == null ? null : 'Joined ${_joined.format(joinedAtUtc)}';

  /// "12 followers · 3 following". Null when either count is unknown.
  static String? followCounts(int? followers, int? following) {
    if (followers == null || following == null) return null;
    return '$followers follower${followers == 1 ? '' : 's'} · '
        '$following following';
  }

  /// "12 responses", "1 response", "No responses yet". Direction-free.
  static String responses(int count) =>
      count == 0
          ? 'No responses yet'
          : '$count response${count == 1 ? '' : 's'}';
}
