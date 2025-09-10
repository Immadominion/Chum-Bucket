import 'package:flutter/material.dart';

/// Custom clipper that creates smooth surface waves for the resolve challenge sheet
class DetailedWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    // Create a more dramatic wave pattern that's definitely visible
    final waveHeight = size.height * 0.65; // Make the base wave higher
    final amplitude = size.height * 0.02; // Larger amplitude for visibility

    // Start from the top left corner
    path.moveTo(0, 0);

    // Create the wave pattern across the width
    final numberOfWaves = 12; // Fewer, larger waves
    final waveLength = size.width / numberOfWaves;

    for (int i = 0; i < numberOfWaves.ceil(); i++) {
      final startX = i * waveLength;
      final endX = ((i + 1) * waveLength).clamp(0.0, size.width);
      final midX = startX + (waveLength / 2);

      if (i == 0) {
        // First wave starts from top
        path.lineTo(0, waveHeight);
      }

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
