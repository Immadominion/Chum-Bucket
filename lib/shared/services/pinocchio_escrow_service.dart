import 'dart:developer';
import 'dart:typed_data';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart' as solana;
import 'package:solana/src/rpc/dto/account_data/account_data.dart';

/// Pinocchio Escrow Service
/// Lightweight service for interacting with the Pinocchio escrow program
/// Works with MWA wallet provider for transaction signing
class PinocchioEscrowService {
  // Pinocchio program ID (deployed to devnet)
  static const String PROGRAM_ID =
      'D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1';

  // Platform fee wallet
  static const String PLATFORM_FEE_WALLET =
      '3yHQosvdAhoFZHs66iFcdfRuT2aApAu6Yst2yoeDNjZm';

  // Constants
  static const int LAMPORTS_PER_SOL = 1000000000;
  static const int MIN_STAKE = 10000000; // 0.01 SOL
  static const int CHALLENGE_ACCOUNT_SIZE = 146;

  // Challenge discriminator
  static const List<int> CHALLENGE_DISCRIMINATOR = [
    0x43,
    0x48,
    0x41,
    0x4C,
    0x4C,
    0x30,
    0x30,
    0x31,
  ]; // "CHALL001"

  // Instruction discriminators
  static const int CREATE_CHALLENGE = 0x01;
  static const int RESOLVE_CHALLENGE = 0x02;
  static const int CANCEL_CHALLENGE = 0x03;

  final solana.SolanaClient _client;

  PinocchioEscrowService({required solana.SolanaClient client})
    : _client = client;

  /// Fetch challenge data from on-chain account
  Future<ChallengeAccount?> getChallengeData(String challengeAddress) async {
    try {
      log('📊 Fetching challenge data for: $challengeAddress');

      final accountInfo = await _client.rpcClient.getAccountInfo(
        challengeAddress,
      );
      if (accountInfo.value == null || accountInfo.value!.data == null) {
        log('⚠️ Challenge account not found or empty');
        return null;
      }

      final rawData = accountInfo.value!.data;
      // AccountData can be BinaryAccountData, ParsedAccountData, or EmptyAccountData
      // We need the binary data
      Uint8List data;
      if (rawData is BinaryAccountData) {
        data = Uint8List.fromList(rawData.data);
      } else {
        log('⚠️ Unexpected data format: ${rawData.runtimeType}');
        return null;
      }

      // Parse challenge account data according to Pinocchio struct layout
      // Layout: discriminator(8) + initiator(32) + witness(32) + platform(32) +
      //         amount(8) + original_amount(8) + platform_fee(8) + deadline(8) +
      //         is_resolved(1) + is_success(1) + is_cancelled(1) + padding(7)

      if (data.length < CHALLENGE_ACCOUNT_SIZE) {
        log(
          '⚠️ Account data too small: ${data.length} < $CHALLENGE_ACCOUNT_SIZE',
        );
        return null;
      }

      // Verify discriminator
      final discriminator = data.sublist(0, 8);
      bool validDiscriminator = true;
      for (int i = 0; i < 8; i++) {
        if (discriminator[i] != CHALLENGE_DISCRIMINATOR[i]) {
          validDiscriminator = false;
          break;
        }
      }
      if (!validDiscriminator) {
        log('⚠️ Invalid challenge discriminator');
        return null;
      }

      // Parse fields
      int offset = 8;

      final initiator = base58encode(data.sublist(offset, offset + 32));
      offset += 32;

      final witness = base58encode(data.sublist(offset, offset + 32));
      offset += 32;

      final platform = base58encode(data.sublist(offset, offset + 32));
      offset += 32;

      final amount = _readU64LE(data, offset);
      offset += 8;

      final originalAmount = _readU64LE(data, offset);
      offset += 8;

      final platformFee = _readU64LE(data, offset);
      offset += 8;

      final deadline = _readU64LE(data, offset);
      offset += 8;

      final isResolved = data[offset] != 0;
      final isSuccess = data[offset + 1] != 0;
      final isCancelled = data[offset + 2] != 0;

      final challenge = ChallengeAccount(
        address: challengeAddress,
        initiator: initiator,
        witness: witness,
        platform: platform,
        amount: amount,
        originalAmount: originalAmount,
        platformFee: platformFee,
        deadline: deadline,
        isResolved: isResolved,
        isSuccess: isSuccess,
        isCancelled: isCancelled,
      );

      log('✅ Challenge data fetched: ${challenge.toJson()}');
      return challenge;
    } catch (e, stackTrace) {
      log('❌ Error fetching challenge data: $e');
      log('📍 Stack trace: $stackTrace');
      return null;
    }
  }

  /// Read unsigned 64-bit little-endian integer from bytes
  int _readU64LE(Uint8List data, int offset) {
    int value = 0;
    for (int i = 0; i < 8; i++) {
      value |= data[offset + i] << (i * 8);
    }
    return value;
  }

  /// Calculate platform fee for a given amount
  /// Simple flat fee: 2.5%, capped at 0.1 SOL (~$20)
  ///
  /// Industry comparison:
  /// - Polymarket: 0% on most markets
  /// - Coinbase: 0.05-0.60%
  /// - Typical prediction markets: 1-3%
  static double calculatePlatformFee(double amountSol) {
    const feePercent = 0.025; // 2.5%
    const maxFeeSol = 0.1; // 0.1 SOL cap (~$20)

    if (amountSol <= 0) return 0.0;

    final fee = amountSol * feePercent;
    return fee.clamp(0.0, maxFeeSol);
  }

  /// Get fee breakdown for display
  static Map<String, double> getFeeBreakdown(double amountSol) {
    final fee = calculatePlatformFee(amountSol);
    final winnerAmount = amountSol - fee;
    final feePercent = amountSol > 0 ? (fee / amountSol) : 0.0;

    return {
      'challengeAmount': amountSol,
      'platformFee': fee,
      'winnerAmount': winnerAmount,
      'feePercentage': feePercent,
    };
  }

  /// Verify program exists on-chain
  Future<bool> verifyProgramExists() async {
    try {
      final accountInfo = await _client.rpcClient.getAccountInfo(PROGRAM_ID);
      final exists = accountInfo.value != null;
      log(exists ? '✅ Program verified on-chain' : '❌ Program not found');
      return exists;
    } catch (e) {
      log('⚠️ Error verifying program: $e');
      return false;
    }
  }
}

/// Represents a challenge account parsed from on-chain data
class ChallengeAccount {
  final String address;
  final String initiator;
  final String witness;
  final String platform;
  final int amount; // Current amount in lamports
  final int originalAmount; // Original stake in lamports
  final int platformFee; // Fee in lamports
  final int deadline; // Unix timestamp
  final bool isResolved;
  final bool isSuccess;
  final bool isCancelled;

  ChallengeAccount({
    required this.address,
    required this.initiator,
    required this.witness,
    required this.platform,
    required this.amount,
    required this.originalAmount,
    required this.platformFee,
    required this.deadline,
    required this.isResolved,
    required this.isSuccess,
    required this.isCancelled,
  });

  double get amountSol => amount / PinocchioEscrowService.LAMPORTS_PER_SOL;
  double get originalAmountSol =>
      originalAmount / PinocchioEscrowService.LAMPORTS_PER_SOL;
  double get platformFeeSol =>
      platformFee / PinocchioEscrowService.LAMPORTS_PER_SOL;

  DateTime get deadlineDate =>
      DateTime.fromMillisecondsSinceEpoch(deadline * 1000);
  bool get isExpired => DateTime.now().isAfter(deadlineDate);
  bool get isActive => !isResolved && !isCancelled;

  String get status {
    if (isCancelled) return 'cancelled';
    if (isResolved) return isSuccess ? 'success' : 'failed';
    if (isExpired) return 'expired';
    return 'active';
  }

  Map<String, dynamic> toJson() => {
    'address': address,
    'initiator': initiator,
    'witness': witness,
    'platform': platform,
    'amountSol': amountSol,
    'originalAmountSol': originalAmountSol,
    'platformFeeSol': platformFeeSol,
    'deadline': deadline,
    'deadlineDate': deadlineDate.toIso8601String(),
    'isResolved': isResolved,
    'isSuccess': isSuccess,
    'isCancelled': isCancelled,
    'status': status,
  };
}
