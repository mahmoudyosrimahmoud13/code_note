import 'package:code_note/helpers/helper_methods.dart';
import 'package:flutter/material.dart';

class CustomIconButton extends StatelessWidget {
  CustomIconButton(
      {super.key,
      required this.icon,
      this.borderColor,
      this.innerColor,
      this.iconColor}) {
    innerColor ??= Theme.of(navigatorKey.currentContext!).colorScheme.surface;
    borderColor ??=
        Theme.of(navigatorKey.currentContext!).colorScheme.onSurface;
    iconColor ??= Theme.of(navigatorKey.currentContext!).colorScheme.primary;
  }
  final IconData icon;
  Color? borderColor;
  Color? innerColor;
  Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: innerColor,
          shape: CircleBorder(side: BorderSide(width: 1, color: borderColor!)),
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 25,
        ));
  }
}
