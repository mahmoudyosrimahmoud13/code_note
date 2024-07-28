import 'package:code_note/helpers/helper_methods.dart';
import 'package:flutter/material.dart';

class CustomIconButton extends StatelessWidget {
  CustomIconButton(
      {super.key,
      this.icon,
      this.text,
      this.borderColor,
      this.innerColor,
      this.iconColor,
      this.iconSize,
      this.onPressed}) {
    innerColor ??= Theme.of(navigatorKey.currentContext!).colorScheme.surface;
    borderColor ??=
        Theme.of(navigatorKey.currentContext!).colorScheme.onSurface;
    iconColor ??= Theme.of(navigatorKey.currentContext!).colorScheme.primary;
    iconSize ??= 25;
  }
  final IconData? icon;
  final String? text;
  final void Function()? onPressed;
  Color? borderColor;
  Color? innerColor;
  Color? iconColor;
  double? iconSize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(2),
      height: iconSize! + 25,
      child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: innerColor,
            shape:
                CircleBorder(side: BorderSide(width: 1, color: borderColor!)),
          ),
          child: icon == null
              ? Text(
                  text!,
                  style: textTheme.bodyLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                )
              : Icon(
                  icon,
                  color: iconColor,
                  size: iconSize,
                )),
    );
  }
}
