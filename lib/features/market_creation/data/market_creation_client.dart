/// `marketCreation.*` over the existing calls BFF transport.
///
/// Identity is the Supabase session carried by [CallsBffTransport]'s token
/// provider, never a request field. Errors are the four [CallsException]
/// classes the call screens already render; a refusal's message is readable
/// server copy and is shown as-is. Request bodies (which can carry a signed
/// transaction) are never logged.
library;

import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';

import 'market_creation_models.dart';

class MarketCreationClient {
  MarketCreationClient({required CallsBffTransport transport})
    : _transport = transport;

  /// The deployed BFF with the session's token. Pass [authToken] null for the
  /// public reads only.
  factory MarketCreationClient.bff({CallsBffAuthTokenProvider? authToken}) =>
      MarketCreationClient(
        transport: CallsBffTransport(authToken: authToken, verbose: false),
      );

  final CallsBffTransport _transport;

  Future<T> _parse<T>(
    Future<Object?> request,
    T Function(Object?) parse,
  ) async {
    final body = await request;
    try {
      return parse(body);
    } on MarketCreationFormatException {
      throw const CallsFailure(
        'The server sent a market we could not read. Update the app or try again.',
      );
    }
  }

  Future<MarketCreationStatus> status() => _parse(
    _transport.query('marketCreation.status'),
    MarketCreationStatus.fromJson,
  );

  Future<MarketProposal> propose(
    MarketDraft draft, {
    required String idempotencyKey,
  }) => _parse(
    _transport.mutate(
      'marketCreation.propose',
      draft.toJson(idempotencyKey: idempotencyKey),
    ),
    MarketProposal.fromJson,
  );

  Future<List<MarketProposal>> mine() => _parse(
    _transport.query('marketCreation.mine'),
    (body) => [
      for (final row in (body as List? ?? const []))
        MarketProposal.fromJson(row),
    ],
  );

  Future<MarketProposal> get(String proposalId) => _parse(
    _transport.query('marketCreation.get', {'proposalId': proposalId}),
    MarketProposal.fromJson,
  );

  Future<MarketProposal> withdraw(String proposalId) => _parse(
    _transport.mutate('marketCreation.withdraw', {'proposalId': proposalId}),
    MarketProposal.fromJson,
  );

  Future<ReviewQueue> reviewQueue() => _parse(
    _transport.query('marketCreation.reviewQueue'),
    ReviewQueue.fromJson,
  );

  Future<MarketProposal> approve(String proposalId) => _parse(
    _transport.mutate('marketCreation.review', {
      'proposalId': proposalId,
      'decision': 'approve',
    }),
    MarketProposal.fromJson,
  );

  Future<MarketProposal> reject(
    String proposalId, {
    required ReviewReason reason,
    String? note,
  }) => _parse(
    _transport.mutate('marketCreation.review', {
      'proposalId': proposalId,
      'decision': 'reject',
      'reason': reason.wire,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }),
    MarketProposal.fromJson,
  );

  Future<PublishReview> preparePublish(String proposalId, String wallet) =>
      _parse(
        _transport.mutate('marketCreation.preparePublish', {
          'proposalId': proposalId,
          'wallet': wallet,
        }),
        PublishReview.fromJson,
      );

  Future<MarketProposal> submitPublish({
    required String proposalId,
    required String sessionId,
    required String signedTransaction,
  }) => _parse(
    _transport.mutate('marketCreation.submitPublish', {
      'proposalId': proposalId,
      'sessionId': sessionId,
      'signedTransaction': signedTransaction,
    }),
    MarketProposal.fromJson,
  );

  Future<MarketProposal> refreshPublish(String proposalId) => _parse(
    _transport.mutate('marketCreation.refreshPublish', {
      'proposalId': proposalId,
    }),
    MarketProposal.fromJson,
  );

  /// Public: who proposed a live market, or null.
  Future<MarketProposer?> proposerOf(String venueMarketId) => _parse(
    _transport.query('marketCreation.byMarket', {
      'venueMarketId': venueMarketId,
    }),
    (body) =>
        body is Map ? MarketProposer.maybeFromJson(body['proposer']) : null,
  );

  void close() => _transport.close();
}
