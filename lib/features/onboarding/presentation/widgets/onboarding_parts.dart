/// Small pieces the onboarding steps share: the coral brand band with the
/// sheet's scallop, avatars that stay round at any width, "how it works"
/// rows, white surfaces, the money line and the consent line.
library;

import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/screens/splash/widgets/splash_marks.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// The coral band from the sheets' header, ending in the same scallop, with
/// the bucket at top-left and (optionally) a character straddling the edge
/// the way avatars straddle a sheet's header. Decorative: no semantics.
class OnboardingBrandBand extends StatelessWidget {
  const OnboardingBrandBand({
    super.key,
    this.height = 168,
    this.artwork,
    this.artworkSize = 136,
  });

  /// Band height below the status bar, before the scallop.
  final double height;
  final ChumbucketStateArtwork? artwork;
  final double artworkSize;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final art = artwork;
    // The character overlaps the scallop by a third of its height; without
    // one, the page still gets air under the scallop.
    final overhang = art == null ? 20.0 : artworkSize / 3;
    return ExcludeSemantics(
      child: SizedBox(
        height: top + height + ChumbucketBandWave.height + overhang,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The gradient stops a pixel short of the wave's foot and the
            // canvas starts a pixel into it, so no antialiased seam shows
            // under the scallop at any pixel ratio.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top + height + ChumbucketBandWave.height - 1,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ChumbucketPrimaryButton.gradient,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top + height,
              child: const ChumbucketBandWave(),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top + height + ChumbucketBandWave.height - 1,
              bottom: 0,
              child: const ColoredBox(color: AppColors.background),
            ),
            Positioned(
              left: OnbSpace.gutter,
              top: top + 14,
              child: const _BandWordmark(),
            ),
            if (art != null)
              Positioned(
                right: OnbSpace.gutter,
                bottom: 0,
                child: OnbReveal(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutBack,
                  rise: 0,
                  scaleFrom: .92,
                  child: ChumbucketStateArt(art, size: artworkSize),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The bucket in a white disc beside the name, on the coral band.
class _BandWordmark extends StatelessWidget {
  const _BandWordmark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
        ),
        // The whole bucket, chimney to doorstep, inside the disc.
        child: const Padding(
          padding: EdgeInsets.only(top: 1),
          child: SplashBucket(size: 28),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'chumbucket',
        textScaler: TextScaler.noScaling,
        style: OnbText.title.copyWith(
          fontSize: 22,
          letterSpacing: -0.8,
          color: AppColors.surface,
        ),
      ),
    ],
  );
}

/// The sheets' scallop, filled with the canvas colour so the band ends in
/// the page rather than in a white sheet.
class ChumbucketBandWave extends StatelessWidget {
  const ChumbucketBandWave({super.key});

  static const double height = DetailedWaveClipper.minBoxHeight + 1;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: DetailedWaveClipper(),
    child: const SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(color: AppColors.background),
    ),
  );
}

/// A person's picture, always a circle, drawn the way people rows draw it
/// elsewhere in the app: their own picture or the avatar they chose, else
/// their initials on pink wash. Never a picture they did not choose.
class OnbAvatar extends StatelessWidget {
  const OnbAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 44,
  });

  /// The name shown beside it (display name, else the @handle).
  final String name;
  final String? imageUrl;
  final double size;

  static String initialsOf(String name) {
    final words =
        name
            .replaceFirst(RegExp(r'^@'), '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
    if (words.isEmpty) return '?';
    String first(String w) => String.fromCharCode(w.runes.first);
    return (words.length == 1
            ? first(words.first)
            : '${first(words.first)}${first(words.last)}')
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.pinkWash,
          image:
              url == null || url.isEmpty
                  ? null
                  : DecorationImage(
                    image: avatarImageProvider(
                      url,
                      logicalSize: size,
                      devicePixelRatio: dpr,
                    ),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  ),
        ),
        alignment: Alignment.center,
        child:
            url == null || url.isEmpty
                ? Text(
                  initialsOf(name),
                  textScaler: TextScaler.noScaling,
                  style: OnbText.name.copyWith(
                    fontSize: size * .38,
                    height: 1,
                    color: AppColors.onPrimaryContainer,
                  ),
                )
                : null,
      ),
    );
  }
}

/// White, 20 radius, flat: content surfaces carry no shadow.
class OnbSurface extends StatelessWidget {
  const OnbSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(OnbSpace.radius),
    ),
    child: child,
  );
}

/// One "how it works" row: a 24dp icon in a 40dp pink-wash circle, a bold
/// lead and its line.
class HowItWorksRow extends StatelessWidget {
  const HowItWorksRow({
    super.key,
    required this.icon,
    required this.lead,
    required this.body,
  });

  final String icon;
  final String lead;
  final String body;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.pinkWash,
            shape: BoxShape.circle,
          ),
          child: BasilIcon(icon, size: 24, color: AppColors.pinkInk),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$lead ', style: OnbText.name),
                  TextSpan(text: body, style: OnbText.bodyInk),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The three rows that say what the product is.
class HowItWorksList extends StatelessWidget {
  const HowItWorksList({super.key, this.animate = true});
  final bool animate;

  @override
  Widget build(BuildContext context) {
    const rows = [
      (
        'comment-plus-outline',
        OnboardingCopy.howCallLead,
        OnboardingCopy.howCallBody,
      ),
      (
        'exchange-outline',
        OnboardingCopy.howSideLead,
        OnboardingCopy.howSideBody,
      ),
      (
        'award-outline',
        OnboardingCopy.howReceiptLead,
        OnboardingCopy.howReceiptBody,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          OnbReveal(
            delay: Duration(milliseconds: animate ? 200 + 40 * i : 0),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            rise: 0,
            child: HowItWorksRow(
              icon: rows[i].$1,
              lead: rows[i].$2,
              body: rows[i].$3,
            ),
          ),
        ],
      ],
    );
  }
}

/// A small line with a leading 16dp icon (money line, offline line, notes).
class OnbIconLine extends StatelessWidget {
  const OnbIconLine({
    super.key,
    required this.icon,
    required this.text,
    this.style,
    this.color = AppColors.textMuted,
  });

  final String icon;
  final String text;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: ExcludeSemantics(child: BasilIcon(icon, size: 16, color: color)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: (style ?? OnbText.small).copyWith(color: color),
        ),
      ),
    ],
  );
}

/// "By continuing, you agree to the Terms of Use and Privacy Policy." Each
/// link is its own 48dp target and opens trust's [LegalLinks] (the same pages
/// Settings → Privacy & data and the website link to).
class OnbConsentLine extends StatelessWidget {
  const OnbConsentLine({super.key, this.opener});

  final UrlOpener? opener;

  @override
  Widget build(BuildContext context) {
    final style = OnbText.meta;
    final link = style.copyWith(
      color: AppColors.pinkInk,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.pinkInk,
    );
    Widget target(String label, Uri uri) => Semantics(
      link: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openExternalLink(context, uri, opener: opener),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(widthFactor: 1, child: Text(label, style: link)),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          OnboardingCopy.signInConsentLead.trim(),
          textAlign: TextAlign.center,
          style: style,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            target(OnboardingCopy.signInTerms, LegalLinks.terms),
            Text(OnboardingCopy.signInConsentJoin.trim(), style: style),
            target(OnboardingCopy.signInPrivacy, LegalLinks.privacy),
          ],
        ),
      ],
    );
  }
}

/// The pink-ink text action under a primary button.
class OnbTextAction extends StatelessWidget {
  const OnbTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.pinkInk,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      ChumbucketTextAction(label: label, onPressed: onPressed, color: color);
}

/// Skeleton block for loading rows — the shape of what is coming, no spinner.
class OnbSkeleton extends StatelessWidget {
  const OnbSkeleton({super.key, this.height = 16, this.width, this.radius = 8});
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    width: width,
    decoration: BoxDecoration(
      color: const Color(0xFFE9EAEC),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
