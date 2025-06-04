import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/screens/profile/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/profile_provider.dart';

Widget friendsChallengeScreenHeader(BuildContext context) {
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
          child: FutureBuilder<String>(
            future:
                Provider.of<AuthProvider>(context, listen: false).currentUser !=
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
                    : Future.value('assets/images/ai_gen/profile_images/1.png'),
            builder: (context, snapshot) {
              return Container(
                width: 32.w,
                height: 32.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(
                    2.w,
                  ), // Space between border and image
                  child: CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                        snapshot.hasData ? AssetImage(snapshot.data!) : null,
                    child:
                        !snapshot.hasData
                            ? Icon(
                              CupertinoIcons.person_fill,
                              size: 18.w,
                              color: Colors.grey[700],
                            )
                            : null,
                  ),
                ),
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
