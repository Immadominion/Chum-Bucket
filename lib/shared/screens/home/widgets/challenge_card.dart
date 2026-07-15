import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';

class ChallengeCard extends StatelessWidget {
  final Map<String, dynamic> challenge;
  final Function(Map<String, dynamic>, bool) onMarkCompleted;

  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final status = (challenge['status'] as String?)?.toLowerCase() ?? 'pending';
    // Use shared utility for consistent status handling
    final isInteractable = ChallengeStatusUtils.isResolvable(status);
    final friendNameRaw = (challenge['friendName'] as String?) ?? 'Unknown';
    final isCurrentUserWitness = challenge['isCurrentUserWitness'] == true;
    final amount = challenge['amount'];
    final amountText = _formatAmount(amount);
    final title = (challenge['title'] as String?) ?? '';
    final description = (challenge['description'] as String?) ?? '';
    final displayText =
        description.isNotEmpty
            ? description
            : title.isNotEmpty
            ? title
            : 'Challenge';

    // Determine prefix based on whether current user is the witness
    final witnessPrefix = isCurrentUserWitness ? 'Witnessed by ' : 'Witness: ';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            // color: _getStatusColor(status).withOpacity(0.1),
            color: Colors.grey.withOpacity(0.2),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with challenge title and amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  displayText[0].toUpperCase() + displayText.substring(1),
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 12.w),
              // Amount with gradient background
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  // gradient: const LinearGradient(
                  //   colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                  //   begin: Alignment.centerLeft,
                  //   end: Alignment.centerRight,
                  // ),
                  color: ChallengeStatusUtils.getStatusColor(status),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '$amountText SOL',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          // Friend info and status row
          Row(
            children: [
              // Friend avatar

              // Friend name - use Expanded instead of nested Row with Flexible
              // If friendName is "You", skip the ResolvedAddressText widget
              Expanded(
                child:
                    isCurrentUserWitness || friendNameRaw == 'You'
                        ? Text(
                          '${witnessPrefix}You',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                        : ResolvedAddressText(
                          addressOrLabel: friendNameRaw,
                          prefix: witnessPrefix,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                        ),
              ),

              SizedBox(width: 12.w),
              if (isInteractable && challenge['expiresAt'] != null) ...[
                Row(
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.clock,
                      size: 16.w,
                      color: Colors.grey.shade600,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      'Expires ${_formatDate(challenge['expiresAt'])}',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';

    DateTime dateTime;
    if (date is DateTime) {
      dateTime = date;
    } else if (date is String) {
      try {
        dateTime = DateTime.parse(date);
      } catch (e) {
        return '';
      }
    } else {
      return '';
    }

    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else {
      return 'soon';
    }
  }

  /// Format amount to display nicely (avoid rounding errors like 0.05 -> 0.1)
  String _formatAmount(dynamic amount) {
    if (amount == null) return '0';
    final value =
        (amount is num)
            ? amount.toDouble()
            : double.tryParse(amount.toString()) ?? 0.0;
    // Remove trailing zeros and limit to 4 decimal places
    if (value == value.truncate()) {
      return value.truncate().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}
