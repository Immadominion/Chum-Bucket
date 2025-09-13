import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class FriendAvatar extends StatelessWidget {
  final String name;
  final String colorHex;
  final VoidCallback onTap;
  final double size;
  final String? imagePath; // Add this parameter

  const FriendAvatar({
    super.key,
    required this.name,
    required this.colorHex,
    required this.onTap,
    this.size = 90,
    this.imagePath,
  });

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.sp,
        height: size.sp,
        decoration: BoxDecoration(
          color: _hexToColor(colorHex),
          shape: BoxShape.circle,
        ),
        child: _buildAvatarContent(),
      ),
    );
  }

  Widget _buildAvatarContent() {
    String imagePathToUse = imagePath ?? _generateImagePathFromName();

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        size.sp / 2,
      ), // Match container's circular shape
      child: Image.asset(
        imagePathToUse,
        fit: BoxFit.cover, // This makes the image cover the full area
        width: size.sp, // Match container width
        height: size.sp, // Match container height
        errorBuilder: (context, error, stackTrace) {
          // If image fails to load, show name initial
          return Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
    );
  }

  String _generateImagePathFromName() {
    // Default to image 1 if no specific logic needed
    // The actual image ID should be passed from the friends list based on order
    return 'assets/images/ai_gen/profile_images/1.png';
  }
}
