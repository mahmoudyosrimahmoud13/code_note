import 'package:code_note/helpers/helper_methods.dart';
import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  CustomButton(
      {super.key,
      required this.text,
      this.icon,
      this.onPressed,
      this.backgroundColor}) {
    backgroundColor ??=
        Theme.of(navigatorKey.currentContext!).colorScheme.primary;
  }
  final String text;
  final Icon? icon;
  final void Function()? onPressed;
  Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return ElevatedButton.icon(
      iconAlignment: IconAlignment.end,
      style: ElevatedButton.styleFrom(backgroundColor: backgroundColor),
      onPressed: onPressed,
      label: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Text(
          text,
          style: textTheme.titleLarge!.copyWith(color: color.onSurface),
        ),
      ),
      icon: icon,
    );
  }
}
