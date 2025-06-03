import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/description_input.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/friend_avatar_section.dart';
import 'package:chumbucket/widgets/friend_avatar.dart';

class BetAmountStep extends StatefulWidget {
  final String friendName;
  final String friendAvatarColor;
  final double betAmount;
  final String description;
  final ValueChanged<double> onBetAmountChanged;

  BetAmountStep({
    super.key,
    required this.friendName,
    required this.friendAvatarColor,
    required this.betAmount,
    required this.description,
    required this.onBetAmountChanged,
  });

  @override
  State<BetAmountStep> createState() => _BetAmountStepState();
}

class _BetAmountStepState extends State<BetAmountStep> {
  late final TextEditingController betAmountController;

  @override
  void initState() {
    super.initState();
    betAmountController = TextEditingController();
  }

  @override
  void dispose() {
    betAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,

      children: [
        Text(
          'How much you want to bet',
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        FriendAvatarSection(
          friendName: widget.friendName,
          friendAvatarColor: widget.friendAvatarColor,
          size: 120.sp,
        ),
        Center(
          child: Column(
            children: [
              ChallengeBetAmountInput(
                controller: betAmountController,
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    widget.onBetAmountChanged(double.tryParse(value) ?? 0.0);
                  } else {
                    widget.onBetAmountChanged(0.0);
                  }
                },
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ],
    );
  }
}
