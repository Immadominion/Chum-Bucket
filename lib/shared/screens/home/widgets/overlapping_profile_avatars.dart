import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_text_styles.dart';

/// The pair of avatars from the reference comp
/// (`assets/images/open_sourced_design_inspiration/irfan/img2.jpeg`):
/// 92dp circles with a white ring, the friend's drawn OVER yours with a 16dp
/// overlap, each name centred under its own circle.
///
/// The pair is centred as a pair. Shifting the second avatar with a transform
/// leaves the row reserving the overlap it no longer uses, which pushes the
/// visible pair 8dp off centre; [Align.widthFactor] gives the overlap back to
/// the row instead.
class OverlappingProfileAvatars extends StatelessWidget {
  final String userImagePath;
  final String friendImagePath;
  final String friendDisplayName;

  const OverlappingProfileAvatars({
    super.key,
    required this.userImagePath,
    required this.friendImagePath,
    required this.friendDisplayName,
  });

  /// Outer diameter, ring included.
  static const double diameter = 92;
  static const double overlap = 16;
  static const double ring = 3.2;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Person(image: userImagePath, name: 'You'),
      // Occupies diameter - overlap in the row and paints its full circle
      // leftwards over yours: later children paint on top.
      Align(
        alignment: Alignment.topRight,
        widthFactor: (diameter - overlap) / diameter,
        child: _Person(image: friendImagePath, name: friendDisplayName),
      ),
    ],
  );
}

class _Person extends StatelessWidget {
  const _Person({required this.image, required this.name});

  final String image;
  final String name;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: OverlappingProfileAvatars.diameter,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: OverlappingProfileAvatars.diameter,
          height: OverlappingProfileAvatars.diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: Colors.white,
              width: OverlappingProfileAvatars.ring,
            ),
          ),
          child: ClipOval(child: Image.asset(image, fit: BoxFit.cover)),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.sheetPersonName,
        ),
      ],
    ),
  );
}
