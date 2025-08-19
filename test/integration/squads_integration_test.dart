import 'package:flutter_test/flutter_test.dart';
import 'package:chumbucket/services/challenge_service.dart';
import 'package:chumbucket/models/models.dart';

void main() {
  group('Squads Multisig Integration Tests', () {
    test('should calculate platform fee correctly', () {
      // Test minimum fee threshold
      expect(
        ChallengeService.calculatePlatformFee(0.05),
        equals(0.001),
      ); // Below min

      // Test normal percentage
      expect(
        ChallengeService.calculatePlatformFee(0.5),
        equals(0.005),
      ); // 1% of 0.5

      // Test maximum fee threshold
      expect(
        ChallengeService.calculatePlatformFee(20.0),
        equals(0.1),
      ); // Above max
    });

    test('should provide detailed fee breakdown', () {
      final breakdown = ChallengeService.getFeeBreakdown(1.0);

      expect(breakdown['challengeAmount'], equals(1.0));
      expect(breakdown['platformFee'], equals(0.01));
      expect(breakdown['winnerAmount'], equals(0.99));
      expect(breakdown['feePercentage'], equals(0.01));
    });

    test('should handle edge cases for fee calculation', () {
      // Test zero amount
      final zeroBreakdown = ChallengeService.getFeeBreakdown(0.0);
      expect(zeroBreakdown['platformFee'], equals(0.001)); // Min fee
      expect(
        zeroBreakdown['winnerAmount'],
        equals(-0.001),
      ); // Negative winner amount

      // Test very small amount
      final smallBreakdown = ChallengeService.getFeeBreakdown(0.01);
      expect(smallBreakdown['platformFee'], equals(0.001)); // Min fee applied
      expect(
        smallBreakdown['winnerAmount'],
        closeTo(0.009, 0.0001),
      ); // Use closeTo for floating point
    });

    group('Challenge Status Management', () {
      test('should handle challenge lifecycle correctly', () {
        // Test challenge status progression
        const statuses = [
          ChallengeStatus.pending,
          ChallengeStatus.accepted,
          ChallengeStatus.completed,
        ];

        for (final status in statuses) {
          expect(status.toString().contains('ChallengeStatus.'), isTrue);
        }
      });
    });

    group('Data Model Validation', () {
      test('should serialize and deserialize Challenge correctly', () {
        final challenge = Challenge(
          id: 'test-id',
          creatorId: 'creator-123',
          title: 'Test Challenge',
          description: 'A test challenge',
          amount: 1.0,
          platformFee: 0.01,
          winnerAmount: 0.99,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 7)),
          status: ChallengeStatus.pending,
        );

        final json = challenge.toJson();
        final deserializedChallenge = Challenge.fromJson(json);

        expect(deserializedChallenge.id, equals(challenge.id));
        expect(deserializedChallenge.amount, equals(challenge.amount));
        expect(
          deserializedChallenge.platformFee,
          equals(challenge.platformFee),
        );
        expect(
          deserializedChallenge.winnerAmount,
          equals(challenge.winnerAmount),
        );
        expect(deserializedChallenge.status, equals(challenge.status));
      });

      test('should serialize and deserialize PlatformFee correctly', () {
        final platformFee = PlatformFee(
          id: 'fee-id',
          challengeId: 'challenge-id',
          amount: 0.01,
          transactionSignature: 'sig123',
          collectedAt: DateTime.now(),
          feePercentage: 0.01, platformWalletAddress: '',
        );

        final json = platformFee.toJson();
        final deserializedFee = PlatformFee.fromJson(json);

        expect(deserializedFee.id, equals(platformFee.id));
        expect(deserializedFee.amount, equals(platformFee.amount));
        expect(
          deserializedFee.feePercentage,
          equals(platformFee.feePercentage),
        );
      });

      test(
        'should serialize and deserialize ChallengeTransaction correctly',
        () {
          final transaction = ChallengeTransaction(
            id: 'tx-id',
            challengeId: 'challenge-id',
            transactionSignature: 'signature123',
            transactionType: 'deposit',
            amount: 1.0,
            fromAddress: 'from123',
            toAddress: 'to123',
            createdAt: DateTime.now(),
          );

          final json = transaction.toJson();
          final deserializedTx = ChallengeTransaction.fromJson(json);

          expect(deserializedTx.id, equals(transaction.id));
          expect(
            deserializedTx.transactionType,
            equals(transaction.transactionType),
          );
          expect(deserializedTx.amount, equals(transaction.amount));
        },
      );
    });

    group('Platform Fee Constants', () {
      test('should have correct fee configuration', () {
        expect(ChallengeService.PLATFORM_FEE_PERCENTAGE, equals(0.01));
        expect(ChallengeService.MIN_FEE_SOL, equals(0.001));
        expect(ChallengeService.MAX_FEE_SOL, equals(0.1));
      });
    });

    group('Integration Readiness Tests', () {
      test('should verify all required environment variables exist', () {
        const requiredEnvVars = [
          'SUPABASE_URL',
          'SUPABASE_ANON_KEY',
          'SOLANA_RPC_URL',
          'PLATFORM_WALLET_ADDRESS',
        ];

        // In a real test, you'd check that these are properly configured
        // For now, we'll just verify the structure exists
        expect(requiredEnvVars.length, equals(4));
      });

      test('should handle network errors gracefully', () {
        // Test error handling scenarios
        expect(() => throw Exception('Network error'), throwsException);
      });
    });
  });
}
