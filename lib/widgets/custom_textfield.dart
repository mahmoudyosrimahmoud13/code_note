import 'package:flutter/material.dart';

class CustomTextfield extends StatelessWidget {
  CustomTextfield(
      {super.key,
      required this.hint,
      this.icon,
      this.iconColor,
      this.textInputType,
      this.validator,
      this.obscureText}) {
    if (obscureText == null) {
      this.obscureText = false;
    }
  }

  final String hint;
  final IconButton? icon;
  final Color? iconColor;
  final TextInputType? textInputType;
  bool? obscureText;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return TextFormField(
        style: TextStyle(color: color.onSurface),
        keyboardType: textInputType,
        obscureText: obscureText!,
        validator: validator,
        decoration: InputDecoration(
            hintText: hint,
            suffixIcon: icon,
            iconColor: iconColor,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(180))));
  }
}
