import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a Basil icon (Iconify, https://icon-sets.iconify.design/basil/)
/// from the bundled SVG set at `assets/icons/basil/`. [icon] is the bare
/// Basil slug, e.g. `'home-outline'` or `'shopping-basket-solid'` — no
/// `basil:` prefix, no `.svg` suffix.
///
/// API mirrors [Icon]/`PhosphorIcon` (positional icon + size/color) so it
/// drops into existing call sites with a mechanical swap.
class BasilIcon extends StatelessWidget {
  const BasilIcon(this.icon, {super.key, this.size, this.color});

  final String icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24.0;
    final resolvedColor = color ?? iconTheme.color;
    return SvgPicture.asset(
      'assets/icons/basil/$icon.svg',
      width: resolvedSize,
      height: resolvedSize,
      colorFilter:
          resolvedColor == null
              ? null
              : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
    );
  }
}
