import 'package:flutter/material.dart';

enum PhosphorIconsStyle { regular, bold }

class PhosphorIcon extends StatelessWidget {
  const PhosphorIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
}

class PhosphorIcons {
  static IconData arrowsClockwise([PhosphorIconsStyle? style]) => Icons.refresh;
  static IconData caretLeft([PhosphorIconsStyle? style]) => Icons.chevron_left;
  static IconData caretRight([PhosphorIconsStyle? style]) =>
      Icons.chevron_right;
  static IconData copy([PhosphorIconsStyle? style]) => Icons.copy;
  static IconData copySimple([PhosphorIconsStyle? style]) => Icons.copy;
  static IconData gearSix([PhosphorIconsStyle? style]) => Icons.settings;
  static IconData info([PhosphorIconsStyle? style]) => Icons.info_outline;
  static IconData paperPlaneTilt([PhosphorIconsStyle? style]) => Icons.send;
  static IconData pencilSimple([PhosphorIconsStyle? style]) => Icons.edit;
  static IconData question([PhosphorIconsStyle? style]) => Icons.help_outline;
  static IconData smileyMeh([PhosphorIconsStyle? style]) =>
      Icons.sentiment_neutral;
  static IconData smileyNervous([PhosphorIconsStyle? style]) =>
      Icons.sentiment_dissatisfied;
  static IconData smileyWink([PhosphorIconsStyle? style]) =>
      Icons.sentiment_satisfied_alt;
  static IconData star([PhosphorIconsStyle? style]) => Icons.star_outline;
  static IconData trash([PhosphorIconsStyle? style]) => Icons.delete_outline;
  static IconData user([PhosphorIconsStyle? style]) => Icons.person_outline;
  static IconData wallet([PhosphorIconsStyle? style]) =>
      Icons.account_balance_wallet_outlined;
  static IconData xCircle([PhosphorIconsStyle? style]) => Icons.cancel_outlined;
}

class PhosphorIconsRegular {
  static const IconData arrowSquareOut = Icons.open_in_new;
  static const IconData arrowRight = Icons.arrow_forward;
  static const IconData caretRight = Icons.chevron_right;
  static const IconData checkCircle = Icons.check_circle_outline;
  static const IconData circle = Icons.circle_outlined;
  static const IconData clock = Icons.schedule;
  static const IconData clockCountdown = Icons.timer_outlined;
  static const IconData hourglass = Icons.hourglass_empty;
  static const IconData prohibit = Icons.block;
  static const IconData user = Icons.person_outline;
  static const IconData wallet = Icons.account_balance_wallet_outlined;
  static const IconData xCircle = Icons.cancel_outlined;
}

class PhosphorIconsFill {
  static const IconData checkCircle = Icons.check_circle;
  static const IconData xCircle = Icons.cancel;
}
