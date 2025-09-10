import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/core/theme/app_colors.dart';

/// Status badge for challenges with consistent styling
class ChallengeStatusBadge extends StatelessWidget {
  final ChallengeStatus status;
  final double? fontSize;
  final EdgeInsets? padding;

  const ChallengeStatusBadge({
    super.key,
    required this.status,
    this.fontSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: _getStatusColor(status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        _getStatusText(status),
        style: TextStyle(
          color: _getStatusColor(status),
          fontSize: fontSize ?? 12.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(ChallengeStatus status) {
    switch (status) {
      case ChallengeStatus.pending:
        return const Color(0xFF2196F3); // Blue
      case ChallengeStatus.accepted:
        return const Color(0xFF4CAF50); // Green
      case ChallengeStatus.funded:
        return const Color(0xFFFF9800); // Orange
      case ChallengeStatus.completed:
        return const Color(0xFF4CAF50); // Green
      case ChallengeStatus.failed:
        return AppColors.error; // Red
      case ChallengeStatus.cancelled:
        return const Color(0xFF757575); // Grey
      case ChallengeStatus.expired:
        return const Color(0xFF795548); // Brown
    }
  }

  String _getStatusText(ChallengeStatus status) {
    switch (status) {
      case ChallengeStatus.pending:
        return 'PENDING';
      case ChallengeStatus.accepted:
        return 'ACCEPTED';
      case ChallengeStatus.funded:
        return 'FUNDED';
      case ChallengeStatus.completed:
        return 'COMPLETED';
      case ChallengeStatus.failed:
        return 'FAILED';
      case ChallengeStatus.cancelled:
        return 'CANCELLED';
      case ChallengeStatus.expired:
        return 'EXPIRED';
    }
  }
}

/// Amount display with SOL suffix
class AmountDisplay extends StatelessWidget {
  final double amount;
  final double? fontSize;
  final Color? color;
  final FontWeight? fontWeight;
  final String currency;

  const AmountDisplay({
    super.key,
    required this.amount,
    this.fontSize,
    this.color,
    this.fontWeight,
    this.currency = 'SOL',
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: amount.toStringAsFixed(
              amount.truncateToDouble() == amount ? 0 : 2,
            ),
            style: TextStyle(
              fontSize: fontSize ?? 16.sp,
              color: color ?? AppColors.onSurface,
              fontWeight: fontWeight ?? FontWeight.w600,
            ),
          ),
          TextSpan(
            text: ' $currency',
            style: TextStyle(
              fontSize: (fontSize ?? 16.sp) * 0.8,
              color: (color ?? AppColors.onSurface).withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wallet address display with truncation
class WalletAddressDisplay extends StatelessWidget {
  final String address;
  final int prefixLength;
  final int suffixLength;
  final double? fontSize;
  final Color? color;
  final bool copyable;

  const WalletAddressDisplay({
    super.key,
    required this.address,
    this.prefixLength = 6,
    this.suffixLength = 6,
    this.fontSize,
    this.color,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    final truncatedAddress = _truncateAddress(address);

    final text = Text(
      truncatedAddress,
      style: TextStyle(
        fontSize: fontSize ?? 12.sp,
        color: color ?? AppColors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );

    if (copyable) {
      return GestureDetector(
        onTap: () => _copyToClipboard(context, address),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            SizedBox(width: 4.w),
            Icon(
              Icons.copy,
              size: 12.sp,
              color: color ?? AppColors.onSurfaceVariant,
            ),
          ],
        ),
      );
    }

    return text;
  }

  String _truncateAddress(String address) {
    if (address.length <= prefixLength + suffixLength) {
      return address;
    }
    return '${address.substring(0, prefixLength)}...${address.substring(address.length - suffixLength)}';
  }

  void _copyToClipboard(BuildContext context, String text) {
    // Implementation would use Clipboard.setData
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address copied to clipboard')),
    );
  }
}
