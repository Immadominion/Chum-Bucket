export 'wallet_export_result.dart';

class Friend {
  final String id;
  final String name;
  final String walletAddress;
  final String avatarUrl;

  Friend({
    required this.id,
    required this.name,
    required this.walletAddress,
    required this.avatarUrl,
  });
}

class Challenge {
  final String id;
  final String creatorId;
  final String? participantId;
  final String? participantEmail;
  final String title;
  final String description;
  final double amount;
  final double platformFee;
  final double winnerAmount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? completedAt;
  final ChallengeStatus status;
  final String? escrowAddress;
  final String? vaultAddress;
  final String? winnerId;
  final String? transactionSignature;
  final String? feeTransactionSignature;

  Challenge({
    required this.id,
    required this.creatorId,
    this.participantId,
    this.participantEmail,
    required this.title,
    required this.description,
    required this.amount,
    required this.platformFee,
    required this.winnerAmount,
    required this.createdAt,
    required this.expiresAt,
    this.completedAt,
    this.status = ChallengeStatus.pending,
    this.escrowAddress,
    this.vaultAddress,
    this.winnerId,
    this.transactionSignature,
    this.feeTransactionSignature,
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      id: json['id'] as String,
      creatorId: json['creator_privy_id'] as String,
      participantId: json['participant_privy_id'] as String?,
      participantEmail: json['participant_email'] as String?,
      title: json['title'] as String,
      description: json['description'] as String,
      amount: (json['amount_sol'] as num).toDouble(),
      platformFee: (json['platform_fee_sol'] as num).toDouble(),
      winnerAmount: (json['winner_amount_sol'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      completedAt:
          json['completed_at'] != null
              ? DateTime.parse(json['completed_at'] as String)
              : null,
      status: ChallengeStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => ChallengeStatus.pending,
      ),
      escrowAddress: json['multisig_address'] as String?,
      vaultAddress: json['vault_address'] as String?,
      winnerId: json['winner_privy_id'] as String?,
      transactionSignature: json['transaction_signature'] as String?,
      feeTransactionSignature: json['fee_transaction_signature'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'creator_privy_id': creatorId,
      'participant_privy_id': participantId,
      'participant_email': participantEmail,
      'title': title,
      'description': description,
      'amount_sol': amount,
      'platform_fee_sol': platformFee,
      'winner_amount_sol': winnerAmount,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'status': status.toString().split('.').last,
      'multisig_address': escrowAddress,
      'vault_address': vaultAddress,
      'winner_privy_id': winnerId,
      'transaction_signature': transactionSignature,
      'fee_transaction_signature': feeTransactionSignature,
    };
  }
}

enum ChallengeStatus {
  pending,
  accepted,
  funded,
  completed,
  failed,
  cancelled,
  expired,
}

class PlatformFee {
  final String id;
  final String challengeId;
  final double amount;
  final String transactionSignature;
  final DateTime collectedAt;
  final double feePercentage;
  final String platformWalletAddress;

  PlatformFee({
    required this.id,
    required this.challengeId,
    required this.amount,
    required this.transactionSignature,
    required this.collectedAt,
    required this.feePercentage,
    required this.platformWalletAddress,
  });

  factory PlatformFee.fromJson(Map<String, dynamic> json) {
    return PlatformFee(
      id: json['id'] as String,
      challengeId: json['challenge_id'] as String,
      amount: (json['amount_sol'] as num).toDouble(),
      transactionSignature: json['transaction_signature'] as String,
      collectedAt: DateTime.parse(json['collected_at'] as String),
      feePercentage: (json['fee_percentage'] as num).toDouble(),
      platformWalletAddress: json['platform_wallet_address'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'challenge_id': challengeId,
      'amount_sol': amount,
      'transaction_signature': transactionSignature,
      'collected_at': collectedAt.toIso8601String(),
      'fee_percentage': feePercentage,
      'platform_wallet_address': platformWalletAddress,
    };
  }
}

class ChallengeTransaction {
  final String id;
  final String challengeId;
  final String transactionSignature;
  final String
  transactionType; // 'deposit', 'release', 'refund', 'platform_fee'
  final double? amount;
  final String? fromAddress;
  final String? toAddress;
  final DateTime createdAt;

  ChallengeTransaction({
    required this.id,
    required this.challengeId,
    required this.transactionSignature,
    required this.transactionType,
    this.amount,
    this.fromAddress,
    this.toAddress,
    required this.createdAt,
  });

  factory ChallengeTransaction.fromJson(Map<String, dynamic> json) {
    return ChallengeTransaction(
      id: json['id'] as String,
      challengeId: json['challenge_id'] as String,
      transactionSignature: json['transaction_signature'] as String,
      transactionType: json['transaction_type'] as String,
      amount:
          json['amount_sol'] != null
              ? (json['amount_sol'] as num).toDouble()
              : null,
      fromAddress: json['from_address'] as String?,
      toAddress: json['to_address'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'challenge_id': challengeId,
      'transaction_signature': transactionSignature,
      'transaction_type': transactionType,
      'amount_sol': amount,
      'from_address': fromAddress,
      'to_address': toAddress,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ChallengeParticipant {
  final String id;
  final String challengeId;
  final String userPrivyId;
  final String role; // 'creator' or 'participant'
  final String walletAddress;
  final DateTime joinedAt;
  final bool hasDeposited;

  ChallengeParticipant({
    required this.id,
    required this.challengeId,
    required this.userPrivyId,
    required this.role,
    required this.walletAddress,
    required this.joinedAt,
    this.hasDeposited = false,
  });

  factory ChallengeParticipant.fromJson(Map<String, dynamic> json) {
    return ChallengeParticipant(
      id: json['id'] as String,
      challengeId: json['challenge_id'] as String,
      userPrivyId: json['user_privy_id'] as String,
      role: json['role'] as String,
      walletAddress: json['wallet_address'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      hasDeposited: json['has_deposited'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'challenge_id': challengeId,
      'user_privy_id': userPrivyId,
      'role': role,
      'wallet_address': walletAddress,
      'joined_at': joinedAt.toIso8601String(),
      'has_deposited': hasDeposited,
    };
  }
}
