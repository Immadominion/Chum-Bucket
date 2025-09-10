import 'package:flutter/material.dart';

class BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white.withOpacity(0.1)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;

    // Draw curved lines
    final path1 = Path();
    path1.moveTo(-50, size.height * 0.3);
    path1.quadraticBezierTo(
      size.width * 0.5,
      size.height * 0.1,
      size.width + 50,
      size.height * 0.4,
    );
    canvas.drawPath(path1, paint);

    final path2 = Path();
    path2.moveTo(-50, size.height * 0.7);
    path2.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.9,
      size.width + 50,
      size.height * 0.6,
    );
    canvas.drawPath(path2, paint);

    // Draw circles
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.2), 30, paint);

    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.8), 20, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
