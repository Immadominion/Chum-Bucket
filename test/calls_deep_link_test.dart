import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/deeplink/call_deep_link.dart';
import 'package:chumbucket/features/calls/deeplink/call_deep_link_router.dart';
import 'package:flutter_test/flutter_test.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

CallDeepLink? parse(String url) => parseCallDeepLink(Uri.parse(url));

void main() {
  group('parsing — links we own', () {
    test('https call links', () {
      for (final url in [
        'https://chumbucket.fun/c/call_ada_btc',
        'https://www.chumbucket.fun/c/call_ada_btc',
        'https://chumbucket.fun/call/call_ada_btc',
      ]) {
        final link = parse(url);
        expect(link, isA<CallLinkTarget>(), reason: url);
        expect((link! as CallLinkTarget).callId, 'call_ada_btc', reason: url);
      }
    });

    test('https person links, with and without the @', () {
      expect((parse('https://chumbucket.fun/u/ada')! as PersonLinkTarget).personRef, 'ada');
      expect(
        (parse('https://chumbucket.fun/u/%40ada')! as PersonLinkTarget).personRef,
        'ada',
      );
      expect(
        (parse('https://chumbucket.fun/person/user_ada')! as PersonLinkTarget)
            .personRef,
        'user_ada',
      );
    });

    test('https market links', () {
      final link = parse('https://chumbucket.fun/m/market_btc_150k');
      expect((link! as MarketLinkTarget).marketId, 'market_btc_150k');
    });

    test('custom-scheme links on both registered schemes', () {
      expect(
        (parse('chumbucket://call/call_1')! as CallLinkTarget).callId,
        'call_1',
      );
      expect((parse('chumbucket://c/call_1')! as CallLinkTarget).callId, 'call_1');
      expect(
        (parse('dev.cleva.chumbucket://u/ada')! as PersonLinkTarget).personRef,
        'ada',
      );
      expect(
        (parse('chumbucket://market/market_1')! as MarketLinkTarget).marketId,
        'market_1',
      );
    });

    test('the ?ref= attribution is carried through, never authorising', () {
      final link = parse('https://chumbucket.fun/c/call_1?ref=@kemi');
      expect(link!.sharedByHandle, 'kemi');
      expect((link as CallLinkTarget).callId, 'call_1');
    });

    test('the kind segment is case-insensitive', () {
      expect(parse('https://chumbucket.fun/C/call_1'), isA<CallLinkTarget>());
      expect(parse('HTTPS://CHUMBUCKET.FUN/u/ada'), isA<PersonLinkTarget>());
    });
  });

  group('parsing — links we must NOT swallow', () {
    test('the Supabase OAuth callback is left alone', () {
      expect(parse('dev.cleva.chumbucket://login-callback'), isNull);
      expect(
        parse('dev.cleva.chumbucket://login-callback#access_token=abc'),
        isNull,
      );
    });

    test('another app\'s scheme is not ours', () {
      expect(parse('someotherapp://c/call_1'), isNull);
      expect(parse('mailto:someone@example.com'), isNull);
    });

    test('another host\'s https link is not ours', () {
      expect(parse('https://example.com/c/call_1'), isNull);
      expect(parse('https://chumbucket.fun.evil.com/c/call_1'), isNull);
    });

    test('the unregistered chumbucket.app domain is not ours', () {
      // It never resolved (NXDOMAIN): no working link was ever built on it, and
      // whoever registers it must not be able to drive the app.
      expect(parse('https://chumbucket.app/c/call_1'), isNull);
      expect(parse('https://www.chumbucket.app/u/ada'), isNull);
      expect(parse('https://link.chumbucket.app/call/call_1'), isNull);
    });

    test('links are built on the live site by default', () {
      final repo = MockCallsRepository();
      expect(repo.shareLinkForCall('call_1'), 'https://chumbucket.fun/c/call_1');
      expect(repo.shareLinkForPerson('ada'), 'https://chumbucket.fun/u/ada');
    });

    test('an unknown kind segment is not ours', () {
      expect(parse('https://chumbucket.fun/settings/theme'), isNull);
      expect(parse('chumbucket://wallet/connect'), isNull);
    });

    test('a missing or empty identifier is refused', () {
      expect(parse('https://chumbucket.fun/c'), isNull);
      expect(parse('https://chumbucket.fun/c/'), isNull);
      expect(parse('chumbucket://call'), isNull);
    });
  });

  group('links we hand out parse back to what they point at', () {
    test('a shared call link round trips', () {
      final repo = MockCallsRepository();
      final url = repo.shareLinkForCall('call_ada_btc');
      final link = parseSharedLink(url);
      expect((link! as CallLinkTarget).callId, 'call_ada_btc');
    });

    test('a shared person link round trips', () {
      final repo = MockCallsRepository();
      final url = repo.shareLinkForPerson('ada');
      final link = parseSharedLink(url);
      expect((link! as PersonLinkTarget).personRef, 'ada');
    });

    test('CallDeepLinkRouter.owns agrees with the parser', () {
      expect(
        CallDeepLinkRouter.owns(Uri.parse('https://chumbucket.fun/c/call_1')),
        isTrue,
      );
      expect(
        CallDeepLinkRouter.owns(
          Uri.parse('dev.cleva.chumbucket://login-callback'),
        ),
        isFalse,
      );
    });
  });

  group('resolution', () {
    late MockCallsRepository repo;
    late CallDeepLinkResolver resolver;

    setUp(() {
      repo = MockCallsRepository();
      resolver = CallDeepLinkResolver(repo);
    });

    test('a call link resolves to that call', () async {
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/c/call_ada_btc'),
        viewerUserId: viewer,
      );
      expect(result, isA<ResolvedCallLink>());
      expect(
        (result as ResolvedCallLink).detail.entry.call.id,
        'call_ada_btc',
      );
    });

    test('a person link resolves by handle to the canonical user id', () async {
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/u/ada?ref=kemi'),
      );
      expect(result, isA<ResolvedPersonLink>());
      final resolved = result as ResolvedPersonLink;
      expect(resolved.detail.person.id, 'user_ada');
      expect(resolved.sharedByHandle, 'kemi');
    });

    test('a market link resolves to that market', () async {
      final result = await resolver.resolve(
        Uri.parse('chumbucket://m/market_btc_150k'),
      );
      expect(result, isA<ResolvedMarketLink>());
      expect(
        (result as ResolvedMarketLink).detail.market.id,
        'market_btc_150k',
      );
    });

    test('resolving works signed out — reading needs no account', () async {
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/c/call_ada_btc'),
      );
      expect(result, isA<ResolvedCallLink>());
    });

    test('a link we do not own reports notOurs so others still see it', () async {
      final result = await resolver.resolve(
        Uri.parse('dev.cleva.chumbucket://login-callback'),
      );
      expect(result, isA<UnresolvedLink>());
      expect(
        (result as UnresolvedLink).reason,
        CallDeepLinkFailure.notOurs,
      );
    });

    test('a missing target reports notFound', () async {
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/c/call_does_not_exist'),
      );
      expect(
        (result as UnresolvedLink).reason,
        CallDeepLinkFailure.notFound,
      );
    });

    test('a followers-only call is notFound for a stranger', () async {
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/c/call_zed_sol'),
      );
      expect(
        (result as UnresolvedLink).reason,
        CallDeepLinkFailure.notFound,
      );
    });

    test('offline is reported as offline, not as notFound', () async {
      repo.simulateOffline = true;
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/c/call_ada_btc'),
      );
      expect(
        (result as UnresolvedLink).reason,
        CallDeepLinkFailure.offline,
      );
    });

    test('a generic failure is reported as failed', () async {
      repo.simulateFailure = true;
      final result = await resolver.resolve(
        Uri.parse('https://chumbucket.fun/u/ada'),
      );
      expect((result as UnresolvedLink).reason, CallDeepLinkFailure.failed);
    });

    test('resolveTarget accepts an already-parsed intent', () async {
      final result = await resolver.resolveTarget(
        const CallLinkTarget('call_ada_btc'),
      );
      expect(result, isA<ResolvedCallLink>());
    });

    test('an unparseable string is not a link', () {
      expect(parseSharedLink('::::not a uri::::'), isNull);
    });

    test('the extension gives a repository the same parsing rules', () {
      final CallsRepository repository = repo;
      expect(
        repository.parseOwnLink(repository.shareLinkForCall('call_1')),
        isA<CallLinkTarget>(),
      );
    });
  });
}
