import 'package:flutter/material.dart';
import 'package:chumbucket/shared/models/models.dart';
import '../models/challenge_status_data.dart';

class ChallengeStatusHelper {
  static ChallengeStatusData getStatusData(ChallengeStatus status) {
    switch (status) {
      case ChallengeStatus.accepted:
        return ChallengeStatusData(
          title: "Challenge Created!",
          message:
              "You have created your challenge. You can share with your friend now, or go back to the home screen.",
          color: Colors.green,
          buttonDescription: "Your challenge is ready to go",
        );
      case ChallengeStatus.funded:
        return ChallengeStatusData(
          title: "Challenge Funded!",
          message: "Your challenge has been funded and is now live.",
          color: Colors.blue,
          buttonDescription: "Your challenge is now funded and active",
        );
      case ChallengeStatus.pending:
        return ChallengeStatusData(
          title: "Creating Challenge...",
          message:
              "We're processing your request. This might take a few seconds.",
          color: Colors.amber,
          buttonDescription: "Processing your challenge",
        );
      case ChallengeStatus.failed:
        return ChallengeStatusData(
          title: "Challenge Failed",
          message: "Something went wrong. Please try again later.",
          color: Colors.red,
          buttonDescription: "Challenge could not be created",
        );
      case ChallengeStatus.completed:
        return ChallengeStatusData(
          title: "Challenge Completed",
          message: "This challenge has been completed.",
          color: Colors.blue,
          buttonDescription: "Congratulations on completing",
        );
      case ChallengeStatus.cancelled:
        return ChallengeStatusData(
          title: "Challenge Cancelled",
          message: "This challenge has been cancelled.",
          color: Colors.orange,
          buttonDescription: "Challenge has been cancelled",
        );
      case ChallengeStatus.expired:
        return ChallengeStatusData(
          title: "Challenge Expired",
          message: "This challenge has expired.",
          color: Colors.orange,
          buttonDescription: "Challenge has expired",
        );
    }
  }
}
