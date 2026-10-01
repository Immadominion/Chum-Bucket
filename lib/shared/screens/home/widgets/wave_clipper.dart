import 'package:flutter/material.dart';

/// The shared scalloped edge for Chumbucket sheets and receipt cards.
class DetailedWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // The old 2%-of-height control point produced <1px of visible curvature.
    // Keep the white edge on the same baseline for older receipt surfaces,
    // with a 14–16px crest-to-trough wave at normal sheet sizes.
    final waveHeight = size.height * 0.65;
    final amplitude = (size.height * .6).clamp(0.0, 16.0);

    // Start on the baseline, without an accidental wedge at the left edge.
    path.moveTo(0, waveHeight);

    // Create the wave pattern across the width
    final numberOfWaves = (size.width / 36).round().clamp(6, 16);
    final waveLength = size.width / numberOfWaves;

    for (int i = 0; i < numberOfWaves.ceil(); i++) {
      final startX = i * waveLength;
      final endX = ((i + 1) * waveLength).clamp(0.0, size.width);
      final midX = startX + (waveLength / 2);

      // Create alternating waves
      final isHighWave = i % 2 == 0;
      final controlY =
          isHighWave ? waveHeight - amplitude : waveHeight + amplitude;

      // Use quadratic bezier for smooth curves
      path.quadraticBezierTo(
        midX.clamp(0.0, size.width),
        controlY,
        endX,
        waveHeight,
      );
    }

    // Complete the path to fill the bottom
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
