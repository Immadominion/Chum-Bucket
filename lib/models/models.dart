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
  final String participantId;
  final double amount;
  final String description;
  final DateTime createdAt;
  final DateTime expiresAt;
  final ChallengeStatus status;

  Challenge({
    required this.id,
    required this.creatorId,
    required this.participantId,
    required this.amount,
    required this.description,
    required this.createdAt,
    required this.expiresAt,
    this.status = ChallengeStatus.pending,
  });
}

enum ChallengeStatus {
  pending,
  accepted,
  completed,
  failed,
  cancelled
}