import 'package:code_note/widgets/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';

class TextBlock extends Block {
  const TextBlock({super.key, required super.id, super.onPressed});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Note'),
            CustomIconButton(
              icon: Icons.delete,
              iconSize: 15,
              innerColor: color.onError,
              iconColor: color.error,
              onPressed: () {
                onPressed!(id);
              },
            )
          ],
        ),
        Container(
          child: TextField(
            decoration: InputDecoration(
              hintText: 'note',
              border: InputBorder.none,
              hintStyle: text.bodyLarge!.copyWith(color: color.onSurface),
            ),
            style: text.bodyLarge!.copyWith(color: color.onSurface),
            minLines: 1,
            maxLines: 1000,
            keyboardType: TextInputType.multiline,
          ),
        ),
      ],
    );
  }
}
