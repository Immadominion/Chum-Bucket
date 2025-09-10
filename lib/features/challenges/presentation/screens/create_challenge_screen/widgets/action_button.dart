import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ActionButton extends StatelessWidget {
  final String text;
  final bool isLoading;
  final VoidCallback onPressed;
  final bool isSecondStep; // Add this parameter
  final String description; // Add this parameter

  const ActionButton({
    super.key,
    required this.text,
    required this.isLoading,
    required this.onPressed,
    this.isSecondStep = false,
    this.description = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        isSecondStep
            ? SizedBox(
              width: MediaQuery.of(context).size.width - 40.w,
              child: Center(
                child: Text(
                  description,
                  softWrap: true,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.08,
                  ),
                ),
              ),
            )
            : GestureDetector(
              onTap: () {
                // TODO: Show configurations
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isSecondStep ? description : 'Configurations',
                    style: TextStyle(
                      color: const Color(0xFFFF3355),
                      fontSize:
                          isSecondStep
                              ? 15.sp
                              : 18.sp, // Smaller font for longer description
                      fontWeight: FontWeight.w600,
                      // Handle long descriptions
                    ),
                  ),
                  Icon(
                    isSecondStep ? Icons.info_outline : Icons.keyboard_arrow_up,
                    color: const Color(0xFFFF3355),
                    size: 20.sp,
                  ),
                ],
              ),
            ),
        SizedBox(height: 20.h),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withAlpha(75),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
              padding: EdgeInsets.symmetric(vertical: 14.h),
            ),
            child:
                isLoading
                    ? SizedBox(
                      height: 20.h,
                      width: 20.h,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : Text(
                      text,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
          ),
        ),
      ],
    );
  }
}
