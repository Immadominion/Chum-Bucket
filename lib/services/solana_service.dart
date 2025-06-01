// import 'package:solana/solana.dart';
// import 'package:flutter/foundation.dart';

// class SolanaService {
//   final SolanaClient _client;

//   SolanaService({required SolanaClient client}) : _client = client;

//   /// Request an airdrop of SOL to the given address (only works on devnet/testnet)
//   Future<String?> requestAirdrop(String address, {int lamports = 1000000000}) async {
//     try {
//       final result = await _client.requestAirdrop(address, lamports);
//       return result;
//     } catch (e) {
//       debugPrint('Error requesting airdrop: $e');
//       return null;
//     }
//   }

//   /// Transfer SOL to another address
//   Future<String?> transferSol({
//     required Ed25519HDKeyPair sender,
//     required String recipient,
//     required int lamports,
//   }) async {
//     try {
//       final recentBlockhash = await _client.rpcClient.getRecentBlockhash();
      
//       final transaction = SystemProgram.transfer(
//         source: sender.publicKey,
//         destination: Ed25519HDPublicKey.fromBase58(recipient),
//         lamports: lamports,
//       );

//       final message = Message(instructions: [transaction]);
//       final signedTx = SignedTx(
//         messageBytes: message.toByteArray(),
//         signatures: [await sender.sign(message.toByteArray())],
//       );

//       final txSignature = await _client.rpcClient.sendTransaction(
//         signedTx.encode(),
//         preflightCommitment: Commitment.confirmed,
//       );
      
//       return txSignature;
//     } catch (e) {
//       debugPrint('Error transferring SOL: $e');
//       return null;
//     }
//   }

//   /// Check if a transaction has been confirmed
//   Future<bool> confirmTransaction(String signature) async {
//     try {
//       final status = await _client.rpcClient.getSignatureStatuses([signature], searchTransactionHistory: true);
//       final txStatus = status.value[0];
//       return txStatus != null && txStatus.confirmationStatus == Commitment.confirmed.name;
//     } catch (e) {
//       debugPrint('Error confirming transaction: $e');
//       return false;
//     }
//   }

//   /// Create a Program Derived Address (PDA) for a challenge
//   Future<String?> createChallengePda({
//     required Ed25519HDKeyPair creator,
//     required String participant,
//     required int lamports,
//     required String description,
//     required DateTime expiryDate,
//   }) async {
//     // This is a placeholder. In a real application, you would:
//     // 1. Design and deploy a Solana program for challenges
//     // 2. Call that program to create a PDA
//     // 3. Transfer funds to the PDA
//     // 4. Store challenge metadata on-chain

//     debugPrint('Creating challenge PDA for: ${creator.address} and $participant');
//     debugPrint('Challenge: $description with $lamports lamports until $expiryDate');
    
//     // In a real implementation, you would return the PDA address
//     return null;
//   }
// }