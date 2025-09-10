import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';

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
    final isPending = status == 'pending';
    final friendNameRaw = (challenge['friendName'] as String?) ?? 'Unknown';
    final amount = challenge['amount'];
    final amountText = amount is num ? amount.toStringAsFixed(1) : '$amount';
    final title = (challenge['title'] as String?) ?? '';
    final description = (challenge['description'] as String?) ?? '';
    final displayText =
        description.isNotEmpty
            ? description
            : title.isNotEmpty
            ? title
            : 'Challenge';

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
                  color: _getStatusColor(status),
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
              Expanded(
                child: ResolvedAddressText(
                  addressOrLabel: friendNameRaw,
                  prefix: 'Witness: ',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                ),
              ),

              SizedBox(width: 12.w),
              if (isPending && challenge['expiresAt'] != null) ...[
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color.fromARGB(
          255,
          241,
          155,
          79,
        ); // Match the primary gradient
      case 'completed':
        return Colors.green.shade600;
      case 'failed':
        return Colors.red.shade600;
      case 'cancelled':
        return Colors.grey.shade600;
      default:
        return const Color(0xFFFF5A76);
    }
  }
}
