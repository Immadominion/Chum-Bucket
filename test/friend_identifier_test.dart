import 'package:chumbucket/shared/models/friend_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact 32-byte Solana address, not a base58-looking string', () {
    const address = '11111111111111111111111111111111';
    expect(FriendIdentifier.parse(address)?.kind, FriendIdentifierKind.wallet);
    expect(FriendIdentifier.parse('${address}1'), isNull);
    expect(FriendIdentifier.parse('00000000000000000000000000000000'), isNull);
  });
  for (final input in [
    ' @Alice_1 ',
    'Alice_1',
    'https://x.com/Alice_1?s=1',
    'twitter.com/Alice_1',
  ]) {
    test('detects and normalizes $input without changing wallet case', () {
      final id = FriendIdentifier.parse(input)!;
      expect(id.kind, FriendIdentifierKind.xHandle);
      expect(id.value, 'alice_1');
    });
  }
  for (final input in [
    '',
    '@@alice',
    'a name',
    'very_long_handle_here',
    'https://evil.com/alice',
    'https://x.com@evil.com/alice',
    'https://x.com:8443/alice',
    'https://x.com/alice/status/1',
    'https://x.com/home',
    'alice.sol',
  ]) {
    test('rejects unsupported or ambiguous identifier: $input', () {
      expect(FriendIdentifier.parse(input), isNull);
    });
  }
  test('supports actual resolver names, not all suffixes', () {
    expect(FriendIdentifier.parse('Alice.SKR')?.value, 'alice.skr');
    expect(
      FriendIdentifier.parse('Alice.SKR')?.kind,
      FriendIdentifierKind.domain,
    );
    expect(FriendIdentifier.parse('not/a.skr'), isNull);
  });
}
