import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  const CustomButton(
      {super.key, required this.text, this.icon, this.onPressed});
  final String text;
  final Icon? icon;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return ElevatedButton.icon(
      iconAlignment: IconAlignment.end,
      style: ElevatedButton.styleFrom(backgroundColor: color.primary),
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
