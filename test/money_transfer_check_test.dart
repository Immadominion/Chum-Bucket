/// The USDC transfer check (money contract section (c)) refuses everything
/// but the reviewed transfer, and no signer — Chumbucket wallet, wallet on
/// this phone, or wallet app — is reached when it does.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/money/data/money_models.dart';
import 'package:chumbucket/features/money/domain/money_transfer_signer.dart';
import 'package:chumbucket/features/money/domain/usdc_transfer_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart'
    show Ed25519HDKeyPair, Ed25519HDPublicKey, Signature, findAssociatedTokenAddress;

const _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _token2022 = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
const _system = '11111111111111111111111111111111';
const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memo = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
const _blockhash = 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k';
const _otherMint = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';

Ed25519HDPublicKey _pk(String b58) => Ed25519HDPublicKey.fromBase58(b58);

Future<String> _wallet(int n) async =>
    (await Ed25519HDKeyPair.fromPrivateKeyBytes(
      privateKey: List<int>.filled(32, n),
    )).address;

Future<String> _usdcOf(String owner, {String mint = _usdc}) async =>
    (await findAssociatedTokenAddress(owner: _pk(owner), mint: _pk(mint)))
        .toBase58();

List<int> _u64(int value) {
  final out = List<int>.filled(8, 0);
  var rest = value;
  for (var i = 0; i < 8; i++) {
    out[i] = rest & 0xff;
    rest >>= 8;
  }
  return out;
}

AccountMeta _w(String key, {bool signer = false}) =>
    AccountMeta(pubKey: _pk(key), isWriteable: true, isSigner: signer);
AccountMeta _r(String key) =>
    AccountMeta(pubKey: _pk(key), isWriteable: false, isSigner: false);

Instruction _limit(int units) => Instruction(
  programId: _pk(_computeBudget),
  accounts: const [],
  data: ByteArray([2, ..._u64(units).take(4)]),
);

Instruction _price(int microLamports) => Instruction(
  programId: _pk(_computeBudget),
  accounts: const [],
  data: ByteArray([3, ..._u64(microLamports)]),
);

late String from;
late String to;
late String attacker;
late String fromUsdc;
late String toUsdc;
late String attackerUsdc;

Instruction _createAta({String? owner, String? account, String payer = ''}) =>
    Instruction(
      programId: _pk(_ata),
      accounts: [
        _w(payer.isEmpty ? from : payer, signer: true),
        _w(account ?? toUsdc),
        _r(owner ?? to),
        _r(_usdc),
        _r(_system),
        _r(_token),
      ],
      data: ByteArray(const [1]),
    );

Instruction _transfer({
  int amount = 5000000,
  int decimals = 6,
  String? source,
  String mint = _usdc,
  String? destination,
  String? authority,
  String program = _token,
  int opcode = 12,
}) => Instruction(
  programId: _pk(program),
  accounts: [
    _w(source ?? fromUsdc),
    _r(mint),
    _w(destination ?? toUsdc),
    AccountMeta(
      pubKey: _pk(authority ?? from),
      isWriteable: false,
      isSigner: (authority ?? from) == from,
    ),
  ],
  data: ByteArray([opcode, ..._u64(amount), if (opcode == 12) decimals]),
);

Uint8List _tx(
  List<Instruction> instructions, {
  String? feePayer,
  bool signed = false,
  bool legacy = false,
}) {
  final message = Message(instructions: instructions);
  final payer = _pk(feePayer ?? from);
  final compiled =
      legacy
          ? message.compile(recentBlockhash: _blockhash, feePayer: payer)
          : message.compileV0(recentBlockhash: _blockhash, feePayer: payer);
  final count = compiled.header.numRequiredSignatures;
  return Uint8List.fromList(
    SignedTx(
      compiledMessage: compiled,
      signatures: [
        for (var i = 0; i < count; i++)
          Signature(List<int>.filled(64, signed ? 1 : 0), publicKey: payer),
      ],
    ).toByteArray().toList(),
  );
}

ExpectedUsdcTransfer _expected({bool createsAccount = false, int amount = 5000000}) =>
    ExpectedUsdcTransfer(
      from: from,
      to: to,
      amountBaseUnits: BigInt.from(amount),
      createsAccount: createsAccount,
    );

Matcher get _refused => throwsA(isA<TransferCheckException>());

void main() {
  setUpAll(() async {
    from = await _wallet(11);
    to = await _wallet(12);
    attacker = await _wallet(13);
    fromUsdc = await _usdcOf(from);
    toUsdc = await _usdcOf(to);
    attackerUsdc = await _usdcOf(attacker);
  });

  group('accepts exactly the reviewed transfer', () {
    test('compute budget + TransferChecked', () async {
      final bytes = _tx([_limit(40000), _price(5000), _transfer()]);
      final message = await checkUsdcTransfer(bytes, _expected());
      expect(message, bytes.sublist(65));
    });

    test('with the receiver\'s USDC account made on the way', () async {
      final bytes = _tx([_limit(60000), _createAta(), _transfer()]);
      await checkUsdcTransfer(bytes, _expected(createsAccount: true));
    });

    test('no compute budget at all', () async {
      await checkUsdcTransfer(_tx([_transfer()]), _expected());
    });
  });

  group('refuses a malicious or mismatched transfer', () {
    final cases = <String, Uint8List Function()>{
      'an extra System transfer to someone else':
          () => _tx([
            _transfer(),
            Instruction(
              programId: _pk(_system),
              accounts: [_w(from, signer: true), _w(attacker)],
              data: ByteArray([2, 0, 0, 0, ..._u64(1000000000)]),
            ),
          ]),
      'USDC sent to another account':
          () => _tx([_transfer(destination: attackerUsdc)]),
      'a different amount': () => _tx([_transfer(amount: 50000000)]),
      'other decimals': () => _tx([_transfer(decimals: 9)]),
      'another mint': () => _tx([_transfer(mint: _otherMint)]),
      'debiting an account that is not the payer\'s':
          () => _tx([_transfer(source: attackerUsdc)]),
      'an authority that is not the payer':
          () => _tx([_transfer(authority: attacker)]),
      'a plain Transfer instead of TransferChecked':
          () => _tx([_transfer(opcode: 3)]),
      'Token-2022 instead of Token': () => _tx([_transfer(program: _token2022)]),
      'an account creation the review did not mention':
          () => _tx([_createAta(), _transfer()]),
      'an account created for someone else':
          () => _tx([
            _createAta(owner: attacker, account: attackerUsdc),
            _transfer(),
          ]),
      'a compute price above the ceiling': () => _tx([_price(2000000), _transfer()]),
      'a compute limit above the ceiling': () => _tx([_limit(250000), _transfer()]),
      'the compute limit twice':
          () => _tx([_limit(1000), _limit(2000), _transfer()]),
      'compute budget after the transfer': () => _tx([_transfer(), _limit(1000)]),
      'a memo riding along':
          () => _tx([
            _transfer(),
            Instruction(
              programId: _pk(_memo),
              accounts: [_r(from)],
              data: ByteArray('hi'.codeUnits),
            ),
          ]),
      'two transfers': () => _tx([_transfer(), _transfer(amount: 1)]),
      'someone else paying the fee (two signers)':
          () => _tx([_transfer()], feePayer: attacker),
      'an already-filled signature slot': () => _tx([_transfer()], signed: true),
      'a legacy (not v0) transaction': () => _tx([_transfer()], legacy: true),
    };
    for (final entry in cases.entries) {
      test(entry.key, () async {
        await expectLater(checkUsdcTransfer(entry.value(), _expected()), _refused);
      });
    }

    test('a missing account creation the review promised', () async {
      await expectLater(
        checkUsdcTransfer(_tx([_transfer()]), _expected(createsAccount: true)),
        _refused,
      );
    });

    test('garbage bytes', () async {
      await expectLater(
        checkUsdcTransfer(Uint8List.fromList(List.filled(120, 7)), _expected()),
        _refused,
      );
    });

    test('a review that differs from what the person asked', () {
      final review = TransferReview(
        from: from,
        to: attacker,
        amountBaseUnits: BigInt.from(5000000),
        createsAccount: false,
      );
      expect(
        () => ExpectedUsdcTransfer.fromReview(
          review,
          from: from,
          to: to,
          amountBaseUnits: BigInt.from(5000000),
        ),
        _refused,
      );
    });
  });

  group('every signer runs the check first', () {
    test('a refused transfer never reaches the wallet', () async {
      var asked = 0;
      final signer = MoneyTransferSigner(
        address: from,
        sign: (unsigned, _) async {
          asked++;
          return Uint8List(64);
        },
      );
      await expectLater(
        signer.signTransfer(_tx([_transfer(destination: attackerUsdc)]), _expected()),
        _refused,
      );
      expect(asked, 0);
    });

    test('a checked transfer is signed in its one slot only', () async {
      final signer = MoneyTransferSigner(
        address: from,
        sign: (unsigned, message) async {
          expect(message, unsigned.sublist(65));
          return Uint8List.fromList(List.filled(64, 4));
        },
      );
      final unsigned = _tx([_transfer()]);
      final signed = await signer.signTransfer(unsigned, _expected());
      expect(signed.sublist(1, 65), List.filled(64, 4));
      expect(signed.sublist(65), unsigned.sublist(65));
    });

    test('a wallet that answers with a different message is refused', () async {
      final other = _tx([_transfer(amount: 1)]);
      final signer = MoneyTransferSigner(
        address: from,
        sign: (_, _) async => Uint8List.fromList(other)..fillRange(1, 65, 4),
      );
      await expectLater(
        signer.signTransfer(_tx([_transfer()]), _expected()),
        throwsA(isA<TransferSignFailed>()),
      );
    });

    test('a signer for another wallet is refused', () async {
      final signer = MoneyTransferSigner(
        address: attacker,
        sign: (_, _) async => Uint8List(64),
      );
      await expectLater(
        signer.signTransfer(_tx([_transfer()]), _expected()),
        _refused,
      );
    });
  });
}
