import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/theme/app_colors.dart';

/// The image for an avatar, decoded at the size it is drawn rather than at
/// its source resolution (the bundled avatars are 256px; a remote one can be
/// any size). `cacheWidth` for a [DecorationImage].
ImageProvider avatarImageProvider(
  String url, {
  required double logicalSize,
  required double devicePixelRatio,
}) {
  final ImageProvider base =
      url.startsWith('assets/') ? AssetImage(url) : NetworkImage(url);
  final px = (logicalSize * devicePixelRatio).ceil().clamp(1, 512);
  return ResizeImage(base, width: px, policy: ResizeImagePolicy.fit);
}

/// Reusable avatar component with consistent sizing and fallback
class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final double size;
  final Color? backgroundColor;
  final Color? textColor;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.size = 40,
    this.backgroundColor,
    this.textColor,
    this.onTap,
  });

  /// Small avatar (24x24)
  const AppAvatar.small({
    super.key,
    this.imageUrl,
    required this.initials,
    this.backgroundColor,
    this.textColor,
    this.onTap,
  }) : size = 24;

  /// Medium avatar (40x40) - default
  const AppAvatar.medium({
    super.key,
    this.imageUrl,
    required this.initials,
    this.backgroundColor,
    this.textColor,
    this.onTap,
  }) : size = 40;

  /// Large avatar (64x64)
  const AppAvatar.large({
    super.key,
    this.imageUrl,
    required this.initials,
    this.backgroundColor,
    this.textColor,
    this.onTap,
  }) : size = 64;

  @override
  Widget build(BuildContext context) {
    // One unit for both axes. `.w` and `.h` scale by different factors on any
    // screen whose aspect ratio differs from the 390x844 design (320dp phones,
    // tablets, split screen), which drew avatars as ellipses.
    final diameter = size.r;
    final avatar = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? _getDefaultColor(initials),
        image:
            imageUrl != null
                ? DecorationImage(
                  image: avatarImageProvider(
                    imageUrl!,
                    logicalSize: diameter,
                    devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(
                          context,
                        ) ??
                        3,
                  ),
                  fit: BoxFit.cover,
                )
                : null,
      ),
      child:
          imageUrl == null
              ? Center(
                child: Text(
                  initials.toUpperCase(),
                  style: TextStyle(
                    color: textColor ?? Colors.white,
                    fontSize: (size * 0.4).sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
              : null,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }

    return avatar;
  }

  Color _getDefaultColor(String text) {
    // Generate a color based on the initials
    final colors = [
      AppColors.primary,
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFF9C27B0),
      const Color(0xFFFF9800),
      const Color(0xFFF44336),
      const Color(0xFF607D8B),
      const Color(0xFF795548),
    ];

    final index = text.hashCode % colors.length;
    return colors[index.abs()];
  }
}

/// Friend avatar with status indicator
class FriendAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final bool isOnline;
  final VoidCallback? onTap;
  final String? statusColor; // For custom status colors

  const FriendAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 40,
    this.isOnline = false,
    this.onTap,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(name);
    final backgroundColor =
        statusColor != null ? _parseColor(statusColor!) : null;

    return Stack(
      children: [
        AppAvatar(
          imageUrl: imageUrl,
          initials: initials,
          size: size,
          onTap: onTap,
          backgroundColor: backgroundColor,
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: (size * 0.25).r,
              height: (size * 0.25).r,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}';
    } else if (parts.isNotEmpty) {
      return parts.first.substring(0, 1);
    }
    return '?';
  }

  Color? _parseColor(String colorString) {
    // Parse color from string format (e.g., "#FF5A76" or color name)
    if (colorString.startsWith('#')) {
      return Color(int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
    }
    // Add more color parsing logic as needed
    return null;
  }
}
