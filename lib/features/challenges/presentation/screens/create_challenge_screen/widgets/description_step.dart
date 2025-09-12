import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/widgets/friend_avatar_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/challenges/presentation/screens/create_challenge_screen/widgets/description_input.dart';

class ChallengeDescriptionStep extends StatefulWidget {
  final String friendName;
  final String friendAddress;
  final String friendAvatarColor;
  final TextEditingController descriptionController; // Add this line

  const ChallengeDescriptionStep({
    super.key,
    required this.friendName,
    required this.friendAddress,
    required this.friendAvatarColor,
    required this.descriptionController, // Add this line
  });

  @override
  State<ChallengeDescriptionStep> createState() =>
      _ChallengeDescriptionStepState();
}

class _ChallengeDescriptionStepState extends State<ChallengeDescriptionStep> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'What is the challenge?',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        FriendAvatarSection(
          friendName: widget.friendName,
          friendAvatarColor: widget.friendAvatarColor,
          size: 120.sp,
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ChallengeDescriptionInput(
            controller: widget.descriptionController,
            fieldKey: const ValueKey('description_input'),
          ),
        ),
      ],
    );
  }
}
