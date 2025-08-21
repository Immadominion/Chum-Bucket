import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/description_input.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/friend_avatar_section.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

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
  double? _solUsdPrice;

  @override
  void initState() {
    super.initState();
    betAmountController = TextEditingController();
    _fetchSolPrice();
  }

  Future<void> _fetchSolPrice() async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final price = (data['solana']?['usd'] as num?)?.toDouble();
        if (price != null && mounted) setState(() => _solUsdPrice = price);
      }
    } catch (_) {
      // ignore network errors for price fetch
    }
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
              // USD equivalent aligned to the right, smaller with opacity
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Opacity(
                    opacity: 0.6,
                    child: Text(
                      _buildUsdText(),
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
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

  String _buildUsdText() {
    if (_solUsdPrice == null || widget.betAmount <= 0) return ' ';
    final usd = widget.betAmount * _solUsdPrice!;
    final formatted = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: 2,
    ).format(usd);
    return '≈ $formatted';
  }

  Widget _buildFeeBreakdown(BuildContext context) {
    // Calculate fee breakdown directly without relying on WalletProvider
    // Use static constants that match the ones in ChallengeService
    const double PLATFORM_FEE_PERCENTAGE = 0.01; // 1%
    const double MIN_FEE_SOL = 0.001; // Minimum fee in SOL
    const double MAX_FEE_SOL = 0.1; // Maximum fee cap

    // Calculate platform fee based on challenge amount
    double platformFee = widget.betAmount * PLATFORM_FEE_PERCENTAGE;

    // Apply min/max constraints
    if (platformFee < MIN_FEE_SOL) {
      platformFee = MIN_FEE_SOL;
    } else if (platformFee > MAX_FEE_SOL) {
      platformFee = MAX_FEE_SOL;
    }

    // Calculate winner amount (challenge amount minus platform fee)
    double winnerAmount = widget.betAmount - platformFee;

    // Calculate effective fee percentage
    double feePercentage = platformFee / widget.betAmount;

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
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
              ),
              Text(
                '${widget.betAmount.toStringAsFixed(4)} SOL',
                style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Platform Fee (${(feePercentage * 100).toStringAsFixed(1)}%):',
                style: TextStyle(fontSize: 12.sp, color: Colors.grey.shade600),
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
  }
}
