import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/themes.dart';

/// A round icon (or short text) button used across the app.
///
/// It is a real Material button, so screen readers announce it, keyboards
/// can reach it, and [tooltip] shows on hover and long-press.
class CustomIconButton extends StatelessWidget {
  const CustomIconButton({
    super.key,
    this.icon,
    this.text,
    this.tooltip,
    this.borderColor,
    this.innerColor,
    this.iconColor,
    this.iconSize,
    this.showBadge = false,
    this.onPressed,
  }) : assert(icon != null || text != null);

  final IconData? icon;
  final String? text;
  final String? tooltip;
  final void Function()? onPressed;
  final Color? borderColor;
  final Color? innerColor;
  final Color? iconColor;
  final double? iconSize;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final size = iconSize ?? 22;
    final box = size + 22;

    final button = IconButton(
      tooltip: tooltip ?? text,
      onPressed: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
      style: IconButton.styleFrom(
        backgroundColor: innerColor ?? color.surfaceContainerHigh,
        foregroundColor: iconColor ?? color.primary,
        minimumSize: Size(box, box),
        fixedSize: Size(box, box),
        padding: EdgeInsets.zero,
        side: borderColor == null ? null : BorderSide(color: borderColor!),
        shape: const CircleBorder(),
      ),
      icon: icon != null
          ? Icon(icon, size: size)
          : Text(
              text!,
              style: TextStyle(
                fontFamily: AppBrand.mono,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: iconColor ?? color.primary,
              ),
            ),
    );

    if (!showBadge) return button;
    return Badge(
      smallSize: 8,
      backgroundColor: context.tokens.pin,
      child: button,
    );
  }
}
