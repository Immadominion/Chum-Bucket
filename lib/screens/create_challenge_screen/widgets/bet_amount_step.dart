import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/description_input.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/friend_avatar_section.dart';
import 'package:chumbucket/providers/wallet_provider.dart';

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
              // Fee breakdown display
              if (widget.betAmount > 0) _buildFeeBreakdown(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeeBreakdown(BuildContext context) {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, child) {
        if (walletProvider.challengeService == null) {
          return const SizedBox.shrink();
        }

        final feeBreakdown = walletProvider.getFeeBreakdown(widget.betAmount);
        final platformFee = feeBreakdown['platformFee'] ?? 0.0;
        final winnerAmount = feeBreakdown['winnerAmount'] ?? widget.betAmount;
        final feePercentage = feeBreakdown['feePercentage'] ?? 0.0;

        return Container(
          margin: EdgeInsets.only(top: 12.h),
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fee Breakdown',
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Challenge Amount:',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    '${widget.betAmount.toStringAsFixed(4)} SOL',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Platform Fee (${(feePercentage * 100).toStringAsFixed(1)}%):',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    '-${platformFee.toStringAsFixed(4)} SOL',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.red.shade600,
                    ),
                  ),
                ],
              ),
              Divider(height: 12.h, color: Colors.grey.shade300),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Winner Receives:',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    '${winnerAmount.toStringAsFixed(4)} SOL',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
