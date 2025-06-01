import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProfileHeader extends StatelessWidget {
  final String username;
  final String bio;

  const ProfileHeader({
    Key? key,
    this.username = "Username",
    this.bio =
        "This is a short bio that describes the user, too long? ellipsis",
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40.w,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.1),
            child: Icon(
              Icons.person,
              size: 40.w,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          SizedBox(width: 16.w),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: TextStyle(
                    fontSize: 24.sp,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(
                  width: 200.w,
                  child: Text(
                    bio,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(120),
                      fontWeight: FontWeight.w700,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
