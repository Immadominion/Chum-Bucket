// Wallet apps (Solflare, Phantom) rewrite what they sign: their own priority
// fee in front, Lighthouse checks after. The phone keeps exactly those rewrites
// and nothing else, against the same vectors the API is tested with
// (chumbucket-social-calls-api/scripts/wallet-amendment-vectors.ts).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chumbucket/features/embedded_wallet/panta_wallet_app.dart';
import 'package:chumbucket/features/panta_trading/domain/wallet_amendment.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';

class _AnsweringWallet implements PantaWalletPort {
  _AnsweringWallet(this.answer);
  final Uint8List answer;
  Uint8List? asked;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    asked = unsigned;
    return answer;
  }
}

void main() {
  final vectors =
      jsonDecode(
            File(
              'test/fixtures/wallet_amendment_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final reviewed = base64Decode(vectors['reviewed'] as String);
  final owner = vectors['owner'] as String;
  final cases = [
    for (final c in vectors['cases'] as List<dynamic>)
      (
        name: (c as Map<String, dynamic>)['name'] as String,
        signed: base64Decode(c['payload'] as String),
        messageAccepted: c['messageAccepted'] as bool,
      ),
  ];

  test('the vectors cover the Solflare shape and refusals', () {
    expect(cases.length, greaterThanOrEqualTo(20));
    expect(
      cases.where((c) => c.messageAccepted).map((c) => c.name),
      contains('Solflare: priority fee in front, Lighthouse checks after'),
    );
    expect(cases.where((c) => !c.messageAccepted).length, greaterThan(10));
  });

  for (final c in cases) {
    test('wallet amendment: ${c.name} -> '
        '${c.messageAccepted ? 'kept' : 'refused'}', () async {
      // The rule itself.
      expect(
        walletAmendmentRefusal(reviewed, c.signed),
        c.messageAccepted ? isNull : isNotNull,
      );

      // The wallet-app port: the answer comes back only when it is the
      // reviewed transaction, or a wallet's own amendment of it.
      final wallet = _AnsweringWallet(c.signed);
      final port = CheckedPantaWalletPort(inner: wallet, check: (_) async {});
      if (c.messageAccepted) {
        expect(await port.signTransaction(reviewed), c.signed);
      } else {
        await expectLater(
          port.signTransaction(reviewed),
          throwsA(
            isA<PantaException>().having(
              (e) => e.code,
              'code',
              PantaErrorCode.walletAltered,
            ),
          ),
        );
      }
      expect(wallet.asked, reviewed);

      // The local check before the server is asked to broadcast.
      const validator = PantaTransactionValidator();
      if (c.messageAccepted) {
        validator.validateSigned(reviewed, c.signed, owner);
      } else {
        expect(
          () => validator.validateSigned(reviewed, c.signed, owner),
          throwsA(isA<PantaException>()),
        );
      }
    });
  }

  test('the device log names what the wallet added, nothing secret', () {
    final solflare =
        cases.firstWhere((c) => c.name.startsWith('Solflare')).signed;
    final line = describeWalletAnswer(reviewed, solflare);
    expect(line, startsWith('wallet amendment; answer v0'));
    expect(line, contains('ComputeB:3/0 ComputeB:2/0'));
    expect(line, contains('L2TExMFK:6/1 L2TExMFK:10/1'));
    final memoDropped =
        cases.firstWhere((c) => c.name == 'Memo dropped').signed;
    expect(
      describeWalletAnswer(reviewed, memoDropped),
      startsWith('reviewed instructions changed; answer v0'),
    );
  });

  test('a bare signature is never an amendment', () {
    expect(adoptWalletAmendment(reviewed, Uint8List(64)..[0] = 1), isNull);
  });

  test('an unsigned answer is never kept', () {
    expect(adoptWalletAmendment(reviewed, reviewed), isNull);
  });

  test('a refused amendment says the wallet changed it, not that it '
      'did not sign', () {
    const error = PantaException(PantaErrorCode.walletAltered);
    expect(error.message, contains('changed the transaction'));
    expect(error.message, isNot(contains('didn')));
  });
}
