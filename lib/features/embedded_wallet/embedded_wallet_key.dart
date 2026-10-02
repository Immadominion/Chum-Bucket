/// A Solana wallet whose key the Chumbucket app makes and keeps on the phone,
/// for people who signed in with Google or X and have no wallet app.
///
/// Non-custodial: the key is generated here, from the operating system's
/// secure random source, and never sent anywhere — not to Chumbucket's server,
/// not to Supabase. The server only ever sees the address and signatures.
///
/// It is a standard 12-word BIP-39 recovery phrase on Solana's usual path
/// (m/44'/501'/0'/0', the first account in Phantom and Solflare), so the same
/// wallet can be opened in any of those apps by importing the phrase — that is
/// the export and the backup.
library;

import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:solana/base58.dart';
import 'package:solana/solana.dart' show Ed25519HDKeyPair;

class EmbeddedWalletException implements Exception {
  const EmbeddedWalletException(this.code, this.message);
  final String code;
  final String message;

  static const invalidPhrase = EmbeddedWalletException(
    'EMBEDDED_PHRASE_INVALID',
    'That isn’t a valid 12-word recovery phrase. Check each word and try again.',
  );

  @override
  String toString() => 'EmbeddedWalletException($code)';
}

class EmbeddedWalletKey {
  EmbeddedWalletKey._(this._mnemonic, this._keyPair);

  /// The account Phantom and Solflare open first for a phrase.
  static const derivationPath = "m/44'/501'/0'/0'";

  final String _mnemonic;
  final Ed25519HDKeyPair _keyPair;

  /// The base58 address. Public.
  String get address => _keyPair.address;

  Uint8List get publicKey => Uint8List.fromList(_keyPair.publicKey.bytes);

  /// The recovery phrase. A secret: shown only behind an explicit reveal, and
  /// never logged — see [toString].
  String get recoveryPhrase => _mnemonic;

  /// A new wallet. [newMnemonic] exists for tests; the app uses bip39's own,
  /// which reads `Random.secure()`.
  static Future<EmbeddedWalletKey> generate({
    String Function()? newMnemonic,
  }) async => fromRecoveryPhrase((newMnemonic ?? bip39.generateMnemonic)());

  /// The wallet a recovery phrase opens. Whitespace and case are forgiven;
  /// a wrong word or checksum is not.
  static Future<EmbeddedWalletKey> fromRecoveryPhrase(String phrase) async {
    final normalized = normalizeRecoveryPhrase(phrase);
    final words = normalized.split(' ');
    if (words.length != 12 || !bip39.validateMnemonic(normalized)) {
      throw EmbeddedWalletException.invalidPhrase;
    }
    final keyPair = await Ed25519HDKeyPair.fromMnemonic(
      normalized,
      account: 0,
      change: 0,
    );
    return EmbeddedWalletKey._(normalized, keyPair);
  }

  static String normalizeRecoveryPhrase(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  /// The 64-byte ed25519 signature over exactly [message].
  Future<Uint8List> sign(List<int> message) async =>
      Uint8List.fromList((await _keyPair.sign(message)).bytes);

  /// The 64-byte secret key (seed then public key), base58 — the "private
  /// key" format Phantom and Solflare import. A secret.
  Future<String> exportPrivateKey() async {
    final data = await _keyPair.extract();
    return base58encode([...data.bytes, ...publicKey]);
  }

  @override
  String toString() => 'EmbeddedWalletKey($address, <secret redacted>)';
}
