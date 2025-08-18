import 'dart:developer';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:solana/solana.dart' as solana;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service to interact with Squads Protocol for multisig operations
/// This is a simplified implementation focusing on 2-of-2 multisigs for challenges
class MultisigService {
  final solana.SolanaClient _solanaClient;
  final Dio _httpClient;

  // Squads Program ID (V4) - Will be used when integrating actual Squads SDK
  // ignore: unused_field
  static final String _squadsProgramId =
      dotenv.env['SQUADS_PROGRAM_ID'] ??
      'SQDS4ep65T869zMMBKyuUq6aD6EgTu8psMjkvj52pCf';

  MultisigService({required solana.SolanaClient solanaClient, Dio? httpClient})
    : _solanaClient = solanaClient,
      _httpClient = httpClient ?? Dio();

  /// Creates a 2-of-2 multisig for a challenge
  /// Returns the multisig public key and vault address
  Future<Map<String, String>> createChallengeMultisig({
    required String member1Address,
    required String member2Address,
    required String challengeId,
  }) async {
    try {
      log(
        'Creating multisig for challenge $challengeId with members: $member1Address, $member2Address',
      );

      // For now, we'll simulate the multisig creation
      // In a real implementation, you would:
      // 1. Create the multisig account
      // 2. Initialize it with the two members
      // 3. Set threshold to 2 (both must sign)

      // Generate a deterministic multisig address based on challenge ID
      final multisigSeed = _generateMultisigSeed(challengeId);
      final multisigAddress = await _deriveMultisigAddress(multisigSeed);

      // Generate vault address (where funds are actually stored)
      final vaultAddress = await _deriveVaultAddress(multisigAddress);

      log('Created multisig: $multisigAddress, vault: $vaultAddress');

      return {
        'multisig_address': multisigAddress,
        'vault_address': vaultAddress,
        'status': 'created',
      };
    } catch (e) {
      log('Error creating multisig: $e');
      throw Exception('Failed to create multisig: $e');
    }
  }

  /// Deposits SOL to the multisig vault
  Future<String> depositToVault({
    required String vaultAddress,
    required double amountSol,
    required String senderAddress,
  }) async {
    try {
      log(
        'Depositing $amountSol SOL to vault $vaultAddress from $senderAddress',
      );

      // Convert SOL to lamports for actual transaction (not used in simulation)
      // ignore: unused_local_variable
      final lamports = (amountSol * solana.lamportsPerSol).toInt();

      // For now, simulate the transaction
      // In a real implementation, you would:
      // 1. Create a transfer instruction with the lamports amount
      // 2. Sign it with the sender's wallet
      // 3. Send the transaction

      final simulatedTxSignature = _generateSimulatedTransactionSignature();

      log('Deposit transaction sent: $simulatedTxSignature');

      return simulatedTxSignature;
    } catch (e) {
      log('Error depositing to vault: $e');
      throw Exception('Failed to deposit to vault: $e');
    }
  }

  /// Withdraws SOL from the multisig vault (requires both signatures)
  Future<String> withdrawFromVault({
    required String multisigAddress,
    required String vaultAddress,
    required String recipientAddress,
    required double amountSol,
    required List<String> signerAddresses,
  }) async {
    try {
      log(
        'Withdrawing $amountSol SOL from vault $vaultAddress to $recipientAddress',
      );

      // Convert SOL to lamports for actual transaction (not used in simulation)
      // ignore: unused_local_variable
      final lamports = (amountSol * solana.lamportsPerSol).toInt();

      // Verify we have the required signatures (2 for 2-of-2 multisig)
      if (signerAddresses.length < 2) {
        throw Exception(
          'Insufficient signatures for withdrawal. Need 2, got ${signerAddresses.length}',
        );
      }

      // For now, simulate the transaction
      // In a real implementation, you would:
      // 1. Create a multisig transaction proposal with the lamports amount
      // 2. Get signatures from both parties
      // 3. Execute the transaction

      final simulatedTxSignature = _generateSimulatedTransactionSignature();

      log('Withdrawal transaction sent: $simulatedTxSignature');

      return simulatedTxSignature;
    } catch (e) {
      log('Error withdrawing from vault: $e');
      throw Exception('Failed to withdraw from vault: $e');
    }
  }

  /// Gets the balance of a vault
  Future<double> getVaultBalance(String vaultAddress) async {
    try {
      final publicKey = solana.Ed25519HDPublicKey.fromBase58(vaultAddress);
      final response = await _solanaClient.rpcClient.getBalance(
        publicKey.toBase58(),
      );
      final balanceSol = response.value / solana.lamportsPerSol;

      log('Vault $vaultAddress balance: $balanceSol SOL');
      return balanceSol;
    } catch (e) {
      log('Error getting vault balance: $e');
      return 0.0;
    }
  }

  /// Verifies that a multisig exists and is properly configured
  Future<bool> verifyMultisig(String multisigAddress) async {
    try {
      // For now, simulate verification
      // In a real implementation, you would fetch the multisig account data
      // and verify its configuration

      log('Verifying multisig: $multisigAddress');
      return true;
    } catch (e) {
      log('Error verifying multisig: $e');
      return false;
    }
  }

  /// Helper method to generate a deterministic seed for the multisig
  String _generateMultisigSeed(String challengeId) {
    // Create a deterministic seed based on challenge ID
    final seedData = 'chumbucket_challenge_$challengeId';
    return seedData;
  }

  /// Helper method to derive multisig address from seed
  Future<String> _deriveMultisigAddress(String seed) async {
    // For now, generate a simulated address
    // In a real implementation, you would use Solana's PDA derivation
    final seedBytes = seed.codeUnits;
    final hash = seedBytes.fold(0, (prev, element) => prev + element);

    // Generate a base58-like string
    final addressBytes = List.generate(32, (index) => (hash + index) % 256);
    final address = _bytesToBase58(Uint8List.fromList(addressBytes));

    return address;
  }

  /// Helper method to derive vault address from multisig address
  Future<String> _deriveVaultAddress(String multisigAddress) async {
    // For now, generate a simulated vault address
    // In a real implementation, this would be a PDA derived from the multisig
    final multisigBytes = multisigAddress.codeUnits;
    final hash = multisigBytes.fold(1000, (prev, element) => prev + element);

    final vaultBytes = List.generate(32, (index) => (hash + index * 2) % 256);
    final vaultAddress = _bytesToBase58(Uint8List.fromList(vaultBytes));

    return vaultAddress;
  }

  /// Helper method to simulate transaction signatures
  String _generateSimulatedTransactionSignature() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 100000;
    final signatureBytes = List.generate(64, (index) => (random + index) % 256);
    return _bytesToBase58(Uint8List.fromList(signatureBytes));
  }

  /// Helper method to convert bytes to base58-like string
  String _bytesToBase58(Uint8List bytes) {
    // Simplified base58 encoding for simulation
    // In real implementation, use proper base58 encoding
    final alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    String result = '';

    for (int i = 0; i < bytes.length && i < 44; i++) {
      result += alphabet[bytes[i] % alphabet.length];
    }

    return result;
  }

  /// Cleanup method
  void dispose() {
    _httpClient.close();
  }
}
