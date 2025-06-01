import 'dart:math';
import 'package:flutter/material.dart';

class SplashBackgroundPainter extends CustomPainter {
  final double animationValue;

  SplashBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.purple.withAlpha((100 * animationValue).toInt())
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    // Animated floating bubbles
    for (int i = 0; i < 8; i++) {
      final offset = Offset(
        (size.width * 0.2) + (i * size.width * 0.15),
        (size.height * 0.3) +
            (50 * animationValue * (i.isEven ? 1 : -1)) +
            (20 * animationValue * i),
      );

      canvas.drawCircle(offset, (10 + (i * 3)) * animationValue, paint);
    }

    // Moving wave pattern
    final wavePath = Path();
    wavePath.moveTo(0, size.height * 0.7);

    for (double x = 0; x <= size.width; x += 20) {
      wavePath.lineTo(
        x,
        size.height * 0.7 +
            (30 *
                animationValue *
                sin(
                  x / size.width * 2 * 3.14159 + animationValue * 2 * 3.14159,
                )),
      );
    }

    canvas.drawPath(wavePath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
