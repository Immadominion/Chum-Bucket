import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The scalloped edge where a sheet's pink header meets its white body.
///
/// Traced off the reference comp
/// (`assets/images/open_sourced_design_inspiration/irfan/img2.jpeg`) column by
/// column: the white edge is a row of round ARCHES, each about 50dp wide and
/// rising ~8dp, meeting the next at a sharp cusp. Broad rounded tops, pointed
/// bottoms — a scallop, not a sine wave. (Rise 7.9dp by the same pixel test
/// that reads this clipper's own output at 7.0dp for 7.3dp, hence 8.2.) Each arch is one quadratic Bezier with
/// its control point above the cusps, so the apex sits exactly [archHeight]
/// above them.
///
/// The geometry is absolute and anchored to the TOP of the clipped box (apex
/// at [topInset], cusps [archHeight] below), so any box at least
/// [minBoxHeight] tall draws the same scallop, and everything under the cusps
/// is solid white.
class DetailedWaveClipper extends CustomClipper<Path> {
  /// Target width of one arch; a 366dp sheet gets seven.
  static const double archWidth = 52;

  /// Crest-to-cusp rise, as measured on the comp.
  static const double archHeight = 8.2;

  /// Keeps the antialiased apex inside the box.
  static const double topInset = 1;

  static const double cuspY = topInset + archHeight;
  static const double minBoxHeight = cuspY + 1;

  static int archesFor(double width) =>
      math.max(3, (width / archWidth).round());

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, cuspY);
    final arches = archesFor(size.width);
    final span = size.width / arches;
    // The control point sits 2x the rise above the cusp line, so the curve's
    // midpoint (the apex) lands exactly archHeight above it.
    final controlY = cuspY - archHeight * 2;
    for (var i = 0; i < arches; i++) {
      final startX = i * span;
      path.quadraticBezierTo(startX + span / 2, controlY, startX + span, cuspY);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
