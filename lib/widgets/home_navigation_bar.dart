import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';

class NavBar extends StatelessWidget {
  const NavBar({
    super.key,
    required this.addNote,
  });
  final void Function() addNote;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 30),
      child: Container(
          height: 60,
          width: 400,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(60)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomIconButton(
                icon: Icons.add,
                iconColor: color.onSecondary,
                borderColor: color.surface,
                innerColor: color.primary,
                onPressed: addNote,
              ),
              CustomIconButton(icon: Icons.edit),
              CustomIconButton(icon: Icons.image),
              CustomIconButton(icon: Icons.workspaces),
            ],
          )),
    );
  }
}
