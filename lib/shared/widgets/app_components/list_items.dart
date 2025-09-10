import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_dimensions.dart';
import 'app_avatar.dart';

/// Standard list tile with consistent styling
class AppListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? backgroundColor;
  final EdgeInsets? contentPadding;

  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.backgroundColor,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: ListTile(
        enabled: enabled,
        onTap: onTap,
        contentPadding:
            contentPadding ??
            EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMedium,
              vertical: AppDimensions.paddingSmall,
            ),
        leading: leading,
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w500,
            color:
                enabled
                    ? AppColors.onSurface
                    : AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        subtitle:
            subtitle != null
                ? Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color:
                        enabled
                            ? AppColors.onSurfaceVariant
                            : AppColors.onSurfaceVariant.withOpacity(0.6),
                  ),
                )
                : null,
        trailing: trailing,
      ),
    );
  }
}

/// Friend list item with avatar and status
class FriendListItem extends StatelessWidget {
  final String name;
  final String? username;
  final String? avatarUrl;
  final bool isOnline;
  final VoidCallback? onTap;
  final Widget? trailing;

  const FriendListItem({
    super.key,
    required this.name,
    this.username,
    this.avatarUrl,
    this.isOnline = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      leading: FriendAvatar(
        name: name,
        imageUrl: avatarUrl,
        isOnline: isOnline,
      ),
      title: name,
      subtitle: username != null ? '@$username' : null,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Challenge list item with details
class ChallengeListItem extends StatelessWidget {
  final String title;
  final String? description;
  final String amount;
  final String status;
  final DateTime? createdAt;
  final VoidCallback? onTap;
  final Widget? statusWidget;

  const ChallengeListItem({
    super.key,
    required this.title,
    this.description,
    required this.amount,
    required this.status,
    this.createdAt,
    this.onTap,
    this.statusWidget,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      title: title,
      subtitle: description ?? _formatDate(createdAt),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          SizedBox(height: 2.h),
          statusWidget ??
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: _getStatusColor(status),
                  ),
                ),
              ),
        ],
      ),
      onTap: onTap,
    );
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Now';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'failed':
        return AppColors.error;
      default:
        return AppColors.onSurfaceVariant;
    }
  }
}

/// Transaction list item
class TransactionListItem extends StatelessWidget {
  final String type;
  final String amount;
  final String? description;
  final DateTime timestamp;
  final bool isIncoming;
  final VoidCallback? onTap;

  const TransactionListItem({
    super.key,
    required this.type,
    required this.amount,
    this.description,
    required this.timestamp,
    required this.isIncoming,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      leading: Container(
        width: 40.w,
        height: 40.h,
        decoration: BoxDecoration(
          color: (isIncoming ? AppColors.success : AppColors.error).withOpacity(
            0.1,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
          color: isIncoming ? AppColors.success : AppColors.error,
          size: 20.sp,
        ),
      ),
      title: type,
      subtitle: description ?? _formatTimestamp(timestamp),
      trailing: Text(
        '${isIncoming ? '+' : '-'}$amount',
        style: TextStyle(
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          color: isIncoming ? AppColors.success : AppColors.error,
        ),
      ),
      onTap: onTap,
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}

/// Simple menu item with icon and action
class MenuListItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Widget? trailing;

  const MenuListItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      leading: Container(
        width: 40.w,
        height: 40.h,
        decoration: BoxDecoration(
          color: (iconColor ?? AppColors.primary).withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor ?? AppColors.primary, size: 20.sp),
      ),
      title: title,
      subtitle: subtitle,
      trailing:
          trailing ??
          Icon(
            Icons.chevron_right,
            color: AppColors.onSurfaceVariant,
            size: 20.sp,
          ),
      onTap: onTap,
    );
  }
}
