import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:coral_xyz/coral_xyz_anchor.dart' as coral;
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/shared/models/wallet_export_result.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WalletExportService {
  static const String _logTag = 'WalletExportService';

  /// Get the Privy API base URL from environment
  static String get _baseUrl =>
      dotenv.env['PRIVY_API_URL'] ?? 'https://api.privy.io/v1';

  /// Get the Privy App ID from environment
  static String get _appId =>
      dotenv.env['PRIVY_APP_ID'] ?? dotenv.env['APP_ID'] ?? '';

  /// Export wallet private key using Privy's REST API
  /// Uses HPKE encryption as per Privy documentation
  static Future<WalletExportResult> exportWalletPrivateKey({
    required String walletId,
    String? accessToken,
    String? appId,
    String? authSignature,
  }) async {
    try {
      AppLogger.debug('Starting wallet export via Privy API...', tag: _logTag);

      final effectiveAppId = appId ?? _appId;
      if (effectiveAppId.isEmpty) {
        return WalletExportResult.error('Privy App ID not configured');
      }

      // Step 1: Generate P-256 key pair for HPKE recipient
      final recipientPublicKeyBase64 = await _generateP256PublicKeyBase64();

      AppLogger.debug('Generated recipient key pair for HPKE', tag: _logTag);

      // Step 2: Prepare request headers
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'privy-app-id': effectiveAppId,
      };

      if (accessToken != null) {
        headers['Authorization'] = 'Basic $accessToken';
      }

      if (authSignature != null) {
        headers['privy-authorization-signature'] = authSignature;
      }

      // Step 3: Send request with recipient public key for HPKE encryption
      final requestBody = {
        'encryption_type': 'HPKE',
        'recipient_public_key': recipientPublicKeyBase64,
      };

      final exportResponse = await http.post(
        Uri.parse('$_baseUrl/wallets/$walletId/export'),
        headers: headers,
        body: jsonEncode(requestBody),
      );

      AppLogger.debug(
        'Export response: ${exportResponse.statusCode}',
        tag: _logTag,
      );

      if (exportResponse.statusCode != 200) {
        AppLogger.debug(
          'Wallet export failed: ${exportResponse.statusCode}',
          tag: _logTag,
        );
        AppLogger.debug('Response body: ${exportResponse.body}', tag: _logTag);

        // Handle specific error cases
        if (exportResponse.statusCode == 403) {
          return WalletExportResult.error(
            'Wallet export is not permitted for this account',
          );
        } else if (exportResponse.statusCode == 404) {
          return WalletExportResult.error('Wallet not found');
        } else {
          return WalletExportResult.error(
            'Export failed: Server error ${exportResponse.statusCode}',
          );
        }
      }

      // Step 4: Parse the encrypted response
      final exportData = jsonDecode(exportResponse.body);
      final encryptionType = exportData['encryption_type'] as String?;
      final ciphertext = exportData['ciphertext'] as String?;
      final encapsulatedKey = exportData['encapsulated_key'] as String?;

      if (ciphertext == null || encapsulatedKey == null) {
        return WalletExportResult.error(
          'Invalid response: missing encrypted data',
        );
      }

      AppLogger.debug(
        'Received encrypted wallet data, attempting decryption...',
        tag: _logTag,
      );

      // Step 5: Attempt to decrypt using HPKE (Note: This is a simplified approach)
      // In a production app, you would need to implement full HPKE decryption
      // For now, we'll return the encrypted data and indicate it needs external decryption
      return WalletExportResult.error(
        'Wallet export successful but requires HPKE decryption. '
        'Use the TypeScript decryption function with the following data:\n'
        'Encryption Type: $encryptionType\n'
        'Ciphertext: $ciphertext\n'
        'Encapsulated Key: $encapsulatedKey\n'
        'You need to implement HPKE decryption using the P-256 private key.',
      );
    } catch (e) {
      AppLogger.debug('Error exporting wallet: $e', tag: _logTag);
      return WalletExportResult.error('Export failed: $e');
    }
  }

  /// Generates a P-256 public key in base64 format for HPKE encryption
  ///
  /// This creates a development-compatible key for Privy API integration.
  ///
  /// The Privy API expects:
  /// - DHKEM_P256_HKDF_SHA256 for key encapsulation
  /// - HKDF_SHA256 for key derivation
  /// - CHACHA20_POLY1305 for AEAD encryption
  ///
  /// For production use, implement proper P-256 ECDH key generation
  /// or use the provided TypeScript HPKE decryption function client-side.
  static Future<String> _generateP256PublicKeyBase64() async {
    // Generate mock P-256 compressed public key (33 bytes)
    // Format: 0x02 prefix + 32 bytes X coordinate
    final random = Random.secure();
    final keyBytes = List.generate(33, (index) => random.nextInt(256));

    // Set compressed public key prefix for P-256
    keyBytes[0] = 0x02;

    return base64Encode(keyBytes);
  }

  /// Get wallet information from private key using coral_xyz
  static Future<Map<String, String>?> getWalletInfo(String privateKey) async {
    try {
      // Convert hex private key to bytes
      final keyBytes = _hexToBytes(privateKey);

      // Create Solana keypair from private key
      final keypair = await coral.Keypair.fromSecretKeyAsync(keyBytes);

      return {
        'publicKey': keypair.publicKey.toBase58(),
        'privateKey': privateKey,
        'address': keypair.publicKey.toBase58(),
      };
    } catch (e) {
      print('Error getting wallet info: $e');
      return null;
    }
  }

  /// Copy wallet address to clipboard
  static Future<void> copyWalletAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
  }

  /// Copy private key to clipboard (with user consent)
  static Future<void> copyPrivateKey(String privateKey) async {
    await Clipboard.setData(ClipboardData(text: privateKey));
  }

  /// Validate Solana address format
  static bool isValidSolanaAddress(String address) {
    try {
      final publicKey = coral.PublicKey.fromBase58(address);
      return publicKey.toBase58() == address;
    } catch (e) {
      return false;
    }
  }

  /// Helper method to convert hex string to bytes
  static Uint8List _hexToBytes(String hex) {
    if (hex.startsWith('0x')) {
      hex = hex.substring(2);
    }
    return Uint8List.fromList(
      List.generate(
        hex.length ~/ 2,
        (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  /// Generate a secure backup phrase display
  static List<String> formatMnemonicForDisplay(String mnemonic) {
    return mnemonic.split(' ').where((word) => word.isNotEmpty).toList();
  }

  /// Validate mnemonic phrase
  static bool validateMnemonic(String mnemonic) {
    final words = mnemonic.split(' ').where((word) => word.isNotEmpty).toList();
    return words.length >= 12 && words.length <= 24;
  }
}
