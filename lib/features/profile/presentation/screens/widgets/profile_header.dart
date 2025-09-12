import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/widgets/profile_picture_selection_modal.dart';

/// Profile header section with gradient background, user avatar, and basic info
class ProfileHeader extends StatelessWidget {
  final String username;
  final String bio;
  final String? profileImagePath;
  final VoidCallback onEditProfile;

  const ProfileHeader({
    super.key,
    required this.username,
    required this.bio,
    this.profileImagePath,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26.r),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.2), offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Profile Avatar with FutureBuilder to load image dynamically
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 3.w,
              ),
            ),
            child: Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                if (authProvider.currentUser == null) {
                  return CircleAvatar(
                    radius: 45.w,
                    backgroundColor: Colors.black.withOpacity(0.2),
                    child: Icon(
                      PhosphorIcons.user(),
                      size: 50.w,
                      color: Colors.black,
                    ),
                  );
                }

                return FutureBuilder<String>(
                  future: Provider.of<ProfileProvider>(
                    context,
                    listen: false,
                  ).getUserPfp(authProvider.currentUser!.id),
                  builder: (context, snapshot) {
                    return GestureDetector(
                      onTap: () async {
                        if (snapshot.hasData) {
                          final selectedImageId =
                              await ProfilePictureSelectionModal.show(
                                context,
                                currentProfilePicture: snapshot.data!,
                              );

                          if (selectedImageId != null) {
                            // Trigger a rebuild by calling setState on parent if available
                            // The FutureBuilder will automatically update with new data
                            (context as Element).markNeedsBuild();
                          }
                        }
                      },
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 45.w,
                            backgroundColor: Colors.black.withOpacity(0.2),
                            backgroundImage:
                                snapshot.hasData && snapshot.data != null
                                    ? AssetImage(snapshot.data!)
                                    : null,
                            child:
                                !snapshot.hasData || snapshot.data == null
                                    ? Icon(
                                      PhosphorIcons.user(),
                                      size: 50.w,
                                      color: Colors.black,
                                    )
                                    : null,
                          ),
                          // Edit indicator
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: EdgeInsets.all(4.r),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.w,
                                ),
                              ),
                              child: Icon(
                                PhosphorIcons.pencilSimple(),
                                color: Colors.white,
                                size: 16.w,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          SizedBox(height: 16.h),

          // Username
          Text(
            username,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 8.h),

          // Bio
          if (bio.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: 280.w),
              child: Text(
                bio == 'null' ? 'Cryptic chad [readacted]' : bio,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.black.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          SizedBox(height: 20.h),

          ChallengeButton(
            createNewChallenge: onEditProfile,
            label: 'Edit Profile',
          ),
        ],
      ),
    );
  }
}
