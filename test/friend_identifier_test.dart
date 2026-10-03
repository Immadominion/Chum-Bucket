import 'package:chumbucket/shared/models/friend_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact 32-byte Solana address, not a base58-looking string', () {
    const address = '11111111111111111111111111111111';
    final id = FriendIdentifier.parse(address)!;
    expect(id.kind, FriendIdentifierKind.wallet);
    expect(id.query, address);
    expect(id.label, '1111…1111');
    expect(FriendIdentifier.parse('${address}1'), isNull);
    expect(FriendIdentifier.parse('00000000000000000000000000000000'), isNull);
  });

  for (final input in [
    'https://x.com/Alice_1?s=1',
    'twitter.com/Alice_1',
    'www.x.com/alice_1/',
    'http://mobile.twitter.com/Alice_1',
    'https://x.com/alice_1/status/1840000000000000000',
  ]) {
    test('an X link means that X account only: $input', () {
      final id = FriendIdentifier.parse(input)!;
      expect(id.kind, FriendIdentifierKind.xLink);
      expect(id.value, 'alice_1');
      expect(id.canBeXHandle, isTrue);
      // A link stays a link, so the server looks up X accounts only.
      expect(id.query, 'https://x.com/alice_1');
      expect(id.label, '@alice_1');
    });
  }

  for (final input in [' @Alice_1 ', 'Alice_1']) {
    test('a bare name can be an X handle or a @username: $input', () {
      final id = FriendIdentifier.parse(input)!;
      expect(id.kind, FriendIdentifierKind.handle);
      expect(id.value, 'alice_1');
      expect(id.canBeXHandle, isTrue);
      expect(id.query, '@alice_1');
    });
  }

  test('a @username longer than X allows is still a @username', () {
    final id = FriendIdentifier.parse('a_really_long_name_1')!;
    expect(id.kind, FriendIdentifierKind.handle);
    expect(id.canBeXHandle, isFalse);
  });

  for (final input in [
    '',
    '@@alice',
    'a name',
    'way_too_long_for_a_username',
    'https://evil.com/alice',
    'https://x.com@evil.com/alice',
    'https://x.com:8443/alice',
    'https://x.com/home',
    'https://x.com/i/web/status/1',
    'https://x.com/',
    'ftp://x.com/alice',
    'alice.sol',
  ]) {
    test('rejects unsupported or ambiguous identifier: $input', () {
      expect(FriendIdentifier.parse(input), isNull);
    });
  }

  test('supports actual resolver names, not all suffixes', () {
    final id = FriendIdentifier.parse('Alice.SKR')!;
    expect(id.value, 'alice.skr');
    expect(id.kind, FriendIdentifierKind.domain);
    // Resolved to a wallet on the device before anything is asked.
    expect(id.query, isNull);
    expect(id.canBeXHandle, isFalse);
    expect(FriendIdentifier.parse('not/a.skr'), isNull);
  });
}
