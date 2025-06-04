import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/profile_provider.dart';
import 'package:chumbucket/screens/profile/edit_profile_screen.dart';

class ProfileHeader extends StatelessWidget {
  final String username;
  final String bio;

  const ProfileHeader({Key? key, required this.username, required this.bio})
    : super(key: key);

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
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) => const EditProfileScreen(showCancelIcon: true),
            ),
          );
        },
        child: Row(
          children: [
            FutureBuilder<String>(
              future:
                  Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          ).currentUser !=
                          null
                      ? Provider.of<ProfileProvider>(
                        context,
                        listen: false,
                      ).getUserPfp(
                        Provider.of<AuthProvider>(
                          context,
                          listen: false,
                        ).currentUser!.id,
                      )
                      : Future.value(
                        'assets/images/ai_gen/profile_images/1.png',
                      ),
              builder: (context, snapshot) {
                return CircleAvatar(
                  radius: 40.w,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.1),
                  backgroundImage:
                      snapshot.hasData ? AssetImage(snapshot.data!) : null,
                  child:
                      !snapshot.hasData
                          ? Icon(
                            CupertinoIcons.person_fill,
                            size: 40.w,
                            color: Theme.of(context).colorScheme.primary,
                          )
                          : null,
                );
              },
            ),
            SizedBox(width: 6.w),
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
      ),
    );
  }
}
