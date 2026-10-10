import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;

import '../data/panta_trading_models.dart';
import 'wallet_amendment.dart';

/// Local structural/message checks, not an on-chain or cryptographic approval.
/// The server must still verify every signature and the exact reviewed message.
class PantaTransactionValidator {
  const PantaTransactionValidator();

  void validateUnsigned(Uint8List bytes, String wallet) {
    final tx = _parse(bytes);
    final index = _walletIndex(tx, wallet);
    _require(tx.signatures[index].bytes.every((byte) => byte == 0));
  }

  void validateSigned(Uint8List unsigned, Uint8List signed, String wallet) {
    final original = _parse(unsigned);
    final result = _parse(signed);
    final index = _walletIndex(original, wallet);
    final sameMessage = _equal(
      original.compiledMessage.toByteArray(),
      result.compiledMessage.toByteArray(),
    );
    // Otherwise only a wallet app's own priority fee and Lighthouse checks
    // (wallet_amendment.dart), still signed by the reviewed fee payer.
    _require(
      sameMessage ||
          (index == 0 &&
              _walletIndex(result, wallet) == 0 &&
              walletAmendmentRefusal(unsigned, signed) == null),
    );
    for (var i = 0; i < result.signatures.length; i++) {
      final signature = result.signatures[i].bytes;
      _require(signature.any((byte) => byte != 0));
      if (i != index) _require(_equal(original.signatures[i].bytes, signature));
    }
  }

  encoder.SignedTx _parse(Uint8List bytes) {
    try {
      _require(bytes.isNotEmpty && bytes.length <= 1232);
      final tx = encoder.SignedTx.fromBytes(bytes);
      _require(
        tx.version == encoder.TransactionVersion.v0 &&
            _equal(tx.toByteArray(), bytes),
      );
      final message = tx.compiledMessage;
      final header = message.header;
      final required = header.numRequiredSignatures;
      _require(
        required > 0 &&
            required <= message.accountKeys.length &&
            tx.signatures.length == required &&
            header.numReadonlySignedAccounts < required &&
            header.numReadonlyUnsignedAccounts <=
                message.accountKeys.length - required,
      );
      final lookups =
          (message as encoder.CompiledMessageV0).addressTableLookups;
      final accountCount =
          message.accountKeys.length +
          lookups.fold<int>(
            0,
            (count, lookup) =>
                count +
                lookup.writableIndexes.length +
                lookup.readonlyIndexes.length,
          );
      _require(accountCount <= 256);
      for (final instruction in message.instructions) {
        _require(
          instruction.programIdIndex < accountCount &&
              instruction.accountKeyIndexes.every(
                (index) => index < accountCount,
              ),
        );
      }
      return tx;
    } catch (_) {
      throw const PantaException(PantaErrorCode.invalidResponse);
    }
  }

  int _walletIndex(encoder.SignedTx tx, String wallet) {
    final index = tx.compiledMessage.accountKeys
        .take(tx.compiledMessage.requiredSignatureCount)
        .toList()
        .indexWhere((key) => key.toBase58() == wallet);
    _require(index >= 0);
    return index;
  }

  bool _equal(Iterable<int> a, Iterable<int> b) {
    final left = a.toList();
    final right = b.toList();
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  void _require(bool condition) {
    if (!condition) throw const PantaException(PantaErrorCode.invalidResponse);
  }
}
