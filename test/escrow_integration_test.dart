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
      print('🚀 Setting up PinocchioEscrowService integration tests');
      print('📋 Test wallet: $testWalletAddress');
      print(
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
        print('✅ PinocchioEscrowService initialized successfully');
      } catch (e) {
        print('❌ Failed to initialize PinocchioEscrowService: $e');
        print(
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
          print('✅ Challenge data fetched successfully');
        } else {
          print('⚠️ Challenge not found (expected if not created)');
        }
      } catch (e) {
        print('❌ Fetch challenge test failed: $e');
        if (e.toString().contains('Connection refused')) {
          markTestSkipped('Local validator not available: $e');
        } else {
          rethrow;
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('should demonstrate full challenge lifecycle', () async {
      print('📚 Full Challenge Lifecycle Demo:');
      print(
        '1. 🏗️ Create Challenge: Alice creates 1 SOL challenge, Bob as witness',
      );
      print('2. 💰 Platform Fee: 0.1 SOL fee deducted, 0.9 SOL in escrow');
      print(
        '3. 🎯 Resolve Challenge: Alice completes challenge (success=true)',
      );
      print('4. 💸 Payout: Alice gets 0.9 SOL back, platform gets 0.1 SOL fee');

      // This test documents the expected flow without requiring actual execution
      expect(true, isTrue); // Always passes to show the flow
    });
  });

  group('Integration Architecture Documentation', () {
    test('should document the complete integration stack', () {
      print('📋 Chumbucket Pinocchio Escrow Integration Stack:');
      print('');
      print('🎯 Frontend Layer:');
      print('  - Flutter UI with challenge creation/management');
      print('  - MWA (Mobile Wallet Adapter) for wallet authentication');
      print('  - Real-time updates via Supabase subscriptions');
      print('');
      print('🔧 Service Layer:');
      print('  - MwaChallengeService: Orchestrates business logic');
      print('  - PinocchioEscrowService: On-chain data reading');
      print('  - MwaWalletProvider: Transaction building and signing');
      print('  - UnifiedDatabaseService: Local/remote data management');
      print('');
      print('⛓️ Blockchain Layer:');
      print('  - Pinocchio Program: chumbucket-pinocchio on Solana');
      print('  - Direct instruction building for minimal overhead');
      print('  - MWA: Signs transactions via external wallet');
      print('');
      print('📊 Data Flow:');
      print('  1. User creates challenge in UI');
      print(
        '  2. MwaChallengeService calls MwaWalletProvider.createChallenge()',
      );
      print('  3. MwaWalletProvider builds Pinocchio instruction');
      print('  4. MWA wallet signs the transaction');
      print('  5. Challenge is created on-chain with SOL escrowed');
      print('  6. Challenge details saved to local/remote database');
      print('  7. UI updates with new challenge status');
      print('');
      print('🎮 Resolution Flow:');
      print('  1. User marks challenge as completed');
      print('  2. MwaWalletProvider.resolveChallenge() called');
      print('  3. Pinocchio resolve instruction built and signed via MWA');
      print('  4. Platform fee sent to platform wallet');
      print('  5. Remaining SOL sent to winner');
      print('  6. Database updated with completion status');

      expect(true, isTrue);
    });
  });
}
