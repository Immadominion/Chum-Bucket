import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

/// Receipt content widget with wave stacking effect
class ReceiptContentWidget extends StatelessWidget {
  final Challenge? challenge;
  final ChallengeStatus status;

  const ReceiptContentWidget({
    super.key,
    required this.challenge,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: 50.h), // Overlap the header
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: Stack(
          children: [
            // Background image - properly contained
            Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: 200.h, maxHeight: 550.h),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.r),
                image: const DecorationImage(
                  image: AssetImage(
                    'assets/images/open_sourced_design_inspiration/3d-texture.JPG',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: _buildReceiptContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptContent() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: Colors.black.withOpacity(0.4),
      ),
      child: Padding(
        padding: EdgeInsets.all(20.r),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Text(
                  'CHALLENGE BUCKET',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              SizedBox(height: 24.r),

              // Challenge Details
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.r),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildChallengeDetails(),
                ),
              ),

              SizedBox(height: 16.r),

              // Footer
              Center(
                child: Text(
                  'Powered by Chumbucket',
                  style: TextStyle(
                    color: AppColors.primary.withOpacity(0.8),
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildChallengeDetails() {
    List<Widget> details = [];

    if (challenge?.id != null) {
      details.addAll([
        _buildReceiptRow('Challenge ID', _truncateAddress(challenge!.id)),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.title != null && challenge!.title.isNotEmpty) {
      details.addAll([
        _buildReceiptRow('Title', challenge!.title),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.description != null && challenge!.description.isNotEmpty) {
      details.addAll([
        _buildReceiptRow('Description', challenge!.description),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.participantId != null) {
      details.addAll([
        _buildReceiptRow(
          'Participant ID',
          _truncateAddress(challenge!.participantId!),
        ),
        SizedBox(height: 10.r),
      ]);
    } else if (challenge?.participantEmail != null) {
      details.addAll([
        _buildReceiptRow('Participant', challenge!.participantEmail!),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.escrowAddress != null) {
      details.addAll([
        _buildReceiptRowWithResolver(
          'Escrow Address',
          challenge!.escrowAddress!,
        ),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.transactionSignature != null) {
      details.addAll([
        _buildReceiptRow(
          'Transaction ID',
          _truncateAddress(challenge!.transactionSignature!),
        ),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.amount != null) {
      details.addAll([
        _buildReceiptRow('Amount', '${challenge!.amount} SOL'),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.platformFee != null) {
      details.addAll([
        _buildReceiptRow('Platform Fee', '${challenge!.platformFee} SOL'),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.winnerAmount != null) {
      details.addAll([
        _buildReceiptRow('Winner Amount', '${challenge!.winnerAmount} SOL'),
        SizedBox(height: 10.r),
      ]);
    }

    if (challenge?.createdAt != null) {
      details.addAll([
        _buildReceiptRow('Created', _formatDateTime(challenge!.createdAt)),
        SizedBox(height: 10.r),
      ]);
    }

    return details;
  }

  Widget _buildReceiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRowWithResolver(String label, String address) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: ResolvedAddressText(
            addressOrLabel: address,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _truncateAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
  }

  String _formatDateTime(DateTime dateTime) {
    return dateTime.toString().substring(0, 19).replaceAll('T', ' ');
  }
}
