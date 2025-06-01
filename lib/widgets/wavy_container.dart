
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class WavyContainer extends StatelessWidget {
  final Widget child;
  final Color color;
  final double height;

  const WavyContainer({
    super.key,
    required this.child,
    required this.color,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24.r),
          topRight: Radius.circular(24.r),
        ),
      ),
      child: Stack(
        children: [
          // The wavy bottom edge
          Positioned(
            bottom: -1,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 20.h),
              painter: WavyPainter(color: color),
            ),
          ),
          // Content
          child,
        ],
      ),
    );
  }
}

class WavyPainter extends CustomPainter {
  final Color color;

  WavyPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height); // Start from bottom-left
    path.lineTo(0, 0); // Draw line to top-left
    
    // Create a wavy bottom edge
    final width = size.width;
    path.quadraticBezierTo(
      width / 4, // Control point x
      size.height * 2, // Control point y
      width / 2, // End point x
      0, // End point y
    );
    
    path.quadraticBezierTo(
      width * 3 / 4, // Control point x
      -size.height * 2, // Control point y (negative to curve upward)
      width, // End point x
      0, // End point y
    );
    
    path.lineTo(width, size.height); // Draw line to bottom-right
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}