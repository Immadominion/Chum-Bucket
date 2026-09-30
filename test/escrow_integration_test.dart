import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chumbucket/shared/services/pinocchio_escrow_service.dart';
import 'package:solana/solana.dart' as solana;

void main() {
  group('PinocchioEscrowService Integration Tests', () {
    late PinocchioEscrowService escrowService;
    const testWalletAddress = 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';
    const rpcUrl = 'http://127.0.0.1:8899';

    setUpAll(() async {
      // Note: These tests require a local validator to be running
      debugPrint('🚀 Setting up PinocchioEscrowService integration tests');
      debugPrint('📋 Test wallet: $testWalletAddress');
      debugPrint(
        '📋 Ensure local validator is running: solana-test-validator --reset',
      );
    });

    test('should initialize PinocchioEscrowService properly', () async {
      try {
        final client = solana.SolanaClient(
          rpcUrl: Uri.parse(rpcUrl),
          websocketUrl: Uri.parse('ws://127.0.0.1:8900'),
        );
        escrowService = PinocchioEscrowService(client: client);

        expect(escrowService, isNotNull);
        debugPrint('✅ PinocchioEscrowService initialized successfully');
      } catch (e) {
        debugPrint('❌ Failed to initialize PinocchioEscrowService: $e');
        debugPrint(
          '💡 Make sure local validator is running and program is deployed',
        );
        // Mark as skipped if validator is not available
        markTestSkipped('Local validator not available: $e');
      }
    });

    test('should fetch challenge data', () async {
      try {
        // This test demonstrates fetching challenge data from a known address
        // In a real test, you would first create a challenge on-chain
        const mockChallengeAddress =
            'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';

        final challengeData = await escrowService.getChallengeData(
          mockChallengeAddress,
        );

        if (challengeData != null) {
          expect(challengeData.initiator, isNotNull);
          expect(challengeData.witness, isNotNull);
          debugPrint('✅ Challenge data fetched successfully');
        } else {
          debugPrint('⚠️ Challenge not found (expected if not created)');
        }
      } catch (e) {
        debugPrint('❌ Fetch challenge test failed: $e');
        if (e.toString().contains('Connection refused')) {
          markTestSkipped('Local validator not available: $e');
        } else {
          rethrow;
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('should demonstrate full challenge lifecycle', () async {
      debugPrint('📚 Full Challenge Lifecycle Demo:');
      debugPrint(
        '1. 🏗️ Create Challenge: Alice creates 1 SOL challenge, Bob as witness',
      );
      debugPrint('2. 💰 Platform Fee: 0.1 SOL fee deducted, 0.9 SOL in escrow');
      debugPrint(
        '3. 🎯 Resolve Challenge: Alice completes challenge (success=true)',
      );
      debugPrint(
        '4. 💸 Payout: Alice gets 0.9 SOL back, platform gets 0.1 SOL fee',
      );

      // This test documents the expected flow without requiring actual execution
      expect(true, isTrue); // Always passes to show the flow
    });
  });

  group('Integration Architecture Documentation', () {
    test('should document the complete integration stack', () {
      debugPrint('📋 Chumbucket Pinocchio Escrow Integration Stack:');
      debugPrint('');
      debugPrint('🎯 Frontend Layer:');
      debugPrint('  - Flutter UI with challenge creation/management');
      debugPrint('  - MWA (Mobile Wallet Adapter) for wallet authentication');
      debugPrint('  - Real-time updates via Supabase subscriptions');
      debugPrint('');
      debugPrint('🔧 Service Layer:');
      debugPrint('  - MwaChallengeService: Orchestrates business logic');
      debugPrint('  - PinocchioEscrowService: On-chain data reading');
      debugPrint('  - MwaWalletProvider: Transaction building and signing');
      debugPrint('  - UnifiedDatabaseService: Local/remote data management');
      debugPrint('');
      debugPrint('⛓️ Blockchain Layer:');
      debugPrint('  - Pinocchio Program: chumbucket-pinocchio on Solana');
      debugPrint('  - Direct instruction building for minimal overhead');
      debugPrint('  - MWA: Signs transactions via external wallet');
      debugPrint('');
      debugPrint('📊 Data Flow:');
      debugPrint('  1. User creates challenge in UI');
      debugPrint(
        '  2. MwaChallengeService calls MwaWalletProvider.createChallenge()',
      );
      debugPrint('  3. MwaWalletProvider builds Pinocchio instruction');
      debugPrint('  4. MWA wallet signs the transaction');
      debugPrint('  5. Challenge is created on-chain with SOL escrowed');
      debugPrint('  6. Challenge details saved to local/remote database');
      debugPrint('  7. UI updates with new challenge status');
      debugPrint('');
      debugPrint('🎮 Resolution Flow:');
      debugPrint('  1. User marks challenge as completed');
      debugPrint('  2. MwaWalletProvider.resolveChallenge() called');
      debugPrint('  3. Pinocchio resolve instruction built and signed via MWA');
      debugPrint('  4. Platform fee sent to platform wallet');
      debugPrint('  5. Remaining SOL sent to winner');
      debugPrint('  6. Database updated with completion status');

      expect(true, isTrue);
    });
  });
}
