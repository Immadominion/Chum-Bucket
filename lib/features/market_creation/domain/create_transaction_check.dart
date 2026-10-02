/// Local structural checks on the Panta create transaction around the wallet.
///
/// The server has already validated the transaction's programs, accounts and
/// fee (policy `panta-create/docs-v1`) and will verify the exact signed message
/// and signature again before broadcasting. These checks only make sure the
/// wallet is asked to sign what was reviewed: one signature, paid by the
/// reviewed wallet, still unsigned; and that it returns that same message,
/// signed. They are not a cryptographic proof of approval.
library;

import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;

class CreateTransactionRejected implements Exception {
  const CreateTransactionRejected();
}

encoder.SignedTx _parse(Uint8List bytes) {
  try {
    if (bytes.isEmpty || bytes.length > 1232) {
      throw const CreateTransactionRejected();
    }
    final tx = encoder.SignedTx.fromBytes(bytes);
    final roundTrip = tx.toByteArray().toList();
    if (roundTrip.length != bytes.length) {
      throw const CreateTransactionRejected();
    }
    for (var i = 0; i < bytes.length; i++) {
      if (roundTrip[i] != bytes[i]) throw const CreateTransactionRejected();
    }
    final message = tx.compiledMessage;
    if (message.header.numRequiredSignatures != 1 ||
        tx.signatures.length != 1 ||
        message.accountKeys.isEmpty) {
      throw const CreateTransactionRejected();
    }
    return tx;
  } on CreateTransactionRejected {
    rethrow;
  } catch (_) {
    throw const CreateTransactionRejected();
  }
}

/// The reviewed create: paid and signed only by [wallet], not yet signed.
void checkUnsignedCreate(Uint8List bytes, String wallet) {
  final tx = _parse(bytes);
  if (tx.compiledMessage.accountKeys.first.toBase58() != wallet ||
      tx.signatures.single.bytes.any((byte) => byte != 0)) {
    throw const CreateTransactionRejected();
  }
}

/// The wallet returned the same message with a signature in the payer slot.
void checkSignedCreate(Uint8List unsigned, Uint8List signed, String wallet) {
  checkUnsignedCreate(unsigned, wallet);
  final before = _parse(unsigned).compiledMessage.toByteArray().toList();
  final tx = _parse(signed);
  final after = tx.compiledMessage.toByteArray().toList();
  if (before.length != after.length) throw const CreateTransactionRejected();
  for (var i = 0; i < before.length; i++) {
    if (before[i] != after[i]) throw const CreateTransactionRejected();
  }
  if (tx.signatures.single.bytes.every((byte) => byte == 0)) {
    throw const CreateTransactionRejected();
  }
}
