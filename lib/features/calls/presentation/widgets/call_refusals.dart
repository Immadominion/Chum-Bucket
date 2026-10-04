/// What a refused lock means to the person who tapped it.
///
/// The BFF renders every refusal as a sentence a person can read, and the
/// transport carries only that sentence (the tRPC code is BAD_REQUEST for
/// most of them). These helpers sort the sentences the call sheets act on —
/// "that's your own call", "you're already on record" — from the ones they
/// only show, and soften the few that name an internal state.
library;

import 'package:chumbucket/features/calls/data/calls_repository.dart';

enum CallRefusal {
  /// Back/Fade/Dare on a call the viewer made (`RESPONSE_SELF`).
  ownCall,

  /// One live call per person per market (`CALL_ALREADY_MADE`).
  alreadyOnRecord,

  /// The same answer to the same call twice (`RESPONSE_DUPLICATE`): a
  /// second Dare, in practice.
  alreadyAnswered,

  /// Panta's price for the market could not be read in time.
  priceUnavailable,

  /// The market stopped taking calls (closed, inside its cut-off, or a
  /// historical venue that is read-only now).
  closed,

  /// The device could not reach the server.
  offline,

  /// The session lapsed.
  signedOut,

  /// Anything else: shown as the server worded it, when it is a sentence.
  other,
}

CallRefusal classifyCallRefusal(CallsException error) {
  if (error is CallsOfflineException) return CallRefusal.offline;
  if (error is CallsSignedOutException) return CallRefusal.signedOut;
  final text = error.message.toLowerCase();
  if (text.contains('your own call')) return CallRefusal.ownCall;
  if (text.contains('already have a live call') ||
      text.contains('already on record')) {
    return CallRefusal.alreadyOnRecord;
  }
  if (text.contains('you have already')) return CallRefusal.alreadyAnswered;
  if (text.contains('price') &&
      (text.contains('stale') ||
          text.contains('missing') ||
          text.contains('available'))) {
    return CallRefusal.priceUnavailable;
  }
  if (text.contains('not accepting new calls') ||
      text.contains('not taking new calls') ||
      text.contains('call window') ||
      text.contains('calls close') ||
      text.contains('use panta only')) {
    return CallRefusal.closed;
  }
  return CallRefusal.other;
}

/// One short line for the sheet. Never names an internal state, and never
/// shows a machine's words (an input check's JSON, a status code, a
/// procedure name).
String callRefusalMessage(CallsException error) => switch (classifyCallRefusal(
  error,
)) {
  CallRefusal.ownCall => 'That’s your own call.',
  CallRefusal.alreadyOnRecord => 'You’re already on record here.',
  CallRefusal.alreadyAnswered => 'You already answered this call.',
  CallRefusal.priceUnavailable =>
    'Panta’s price is updating. Try again in a moment.',
  CallRefusal.closed => 'This market stopped taking calls.',
  CallRefusal.offline => 'No connection. Try again when you’re back.',
  CallRefusal.signedOut => 'Sign in again to lock this.',
  CallRefusal.other =>
    _readable(error) ? error.message.trim() : kCallUnexpectedFailure,
};

/// A refusal the server worded for a person: a [CallsRejectedException]
/// whose text is a short sentence. A server failure ([CallsFailure]) or an
/// input check's JSON issue list is not.
bool _readable(CallsException error) {
  if (error is! CallsRejectedException) return false;
  final text = error.message.trim();
  if (text.isEmpty || text.length > 200) return false;
  return !text.startsWith('[') && !text.startsWith('{');
}

/// For a failure that is not a [CallsException] at all: the sheet still
/// stops and says so.
const kCallUnexpectedFailure = 'That didn’t go through. Try again.';
