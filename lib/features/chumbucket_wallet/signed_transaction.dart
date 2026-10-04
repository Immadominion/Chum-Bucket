/// A signer's answer, held to the transaction it was asked to sign.
///
/// Embedded-wallet SDKs answer a signing request either with the whole signed
/// transaction or with the bare signature. Either way the result must be
/// exactly [unsigned] with one signature slot filled: same length, same
/// message, every other slot untouched. Anything else is refused before it can
/// reach the BFF.
library;

import 'dart:typed_data';

class SignedTransactionMismatch implements Exception {
  const SignedTransactionMismatch();
}

/// Signature count and where the message starts: `[compact-u16 n][n × 64][message]`.
({int count, int messageOffset}) signatureSection(Uint8List tx) {
  var count = 0;
  var offset = 0;
  for (var shift = 0; shift < 21; shift += 7) {
    if (offset >= tx.length) throw const SignedTransactionMismatch();
    final byte = tx[offset++];
    count |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) break;
    if (shift == 14) throw const SignedTransactionMismatch();
  }
  final messageOffset = offset + count * 64;
  if (count == 0 || messageOffset >= tx.length) {
    throw const SignedTransactionMismatch();
  }
  return (count: count, messageOffset: messageOffset);
}

/// [unsigned] signed in [slot], from [answer] (whole transaction or bare
/// 64-byte signature). Throws [SignedTransactionMismatch] otherwise.
Uint8List adoptSignerAnswer(
  Uint8List unsigned,
  Uint8List answer, {
  int slot = 0,
}) {
  final before = signatureSection(unsigned);
  if (slot < 0 || slot >= before.count) throw const SignedTransactionMismatch();
  final slotStart = before.messageOffset - (before.count - slot) * 64;
  final Uint8List signed;
  if (answer.length == 64) {
    signed = Uint8List.fromList(unsigned)
      ..setRange(slotStart, slotStart + 64, answer);
  } else {
    signed = Uint8List.fromList(answer);
  }
  final after = signatureSection(signed);
  if (signed.length != unsigned.length ||
      after.count != before.count ||
      after.messageOffset != before.messageOffset) {
    throw const SignedTransactionMismatch();
  }
  for (var i = before.messageOffset; i < unsigned.length; i++) {
    if (signed[i] != unsigned[i]) throw const SignedTransactionMismatch();
  }
  for (var n = 0; n < before.count; n++) {
    final start = before.messageOffset - (before.count - n) * 64;
    var changed = false;
    var empty = true;
    for (var i = start; i < start + 64; i++) {
      if (signed[i] != unsigned[i]) changed = true;
      if (signed[i] != 0) empty = false;
    }
    if (n == slot ? empty : changed) throw const SignedTransactionMismatch();
  }
  return signed;
}
