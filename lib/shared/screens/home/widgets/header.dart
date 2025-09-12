import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';

Widget homeScreenHeader(BuildContext context) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 16.h),
    child: Row(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => ProfileScreen()));
          },
          child: Consumer2<AuthProvider, ProfileProvider>(
            builder: (context, authProvider, profileProvider, child) {
              if (authProvider.currentUser == null) {
                return Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                    border: Border.all(color: Colors.grey[300]!, width: 1.w),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(2.w),
                    child: CircleAvatar(
                      backgroundColor: Colors.grey[300],
                      child: PhosphorIcon(
                        PhosphorIconsRegular.user,
                        size: 18.w,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                );
              }

              return FutureBuilder<String>(
                future: profileProvider.getUserPfp(
                  authProvider.currentUser!.id,
                ),
                builder: (context, snapshot) {
                  return Container(
                    width: 42.w,
                    height: 42.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                      border: Border.all(color: Colors.grey[300]!, width: 1.w),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(2.w),
                      child: CircleAvatar(
                        backgroundColor: Colors.grey[300],
                        backgroundImage:
                            snapshot.hasData
                                ? AssetImage(snapshot.data!)
                                : null,
                        child:
                            !snapshot.hasData
                                ? PhosphorIcon(
                                  PhosphorIconsRegular.user,
                                  size: 18.w,
                                  color: Colors.grey[700],
                                )
                                : null,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Spacer(),
        Text(
          'Wallet',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    ),
  );
}
