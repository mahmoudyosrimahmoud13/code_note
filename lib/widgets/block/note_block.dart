import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';

// ignore: must_be_immutable
class NoteBlock extends Block {
  NoteBlock({
    super.key,
    required super.id,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.text,
  }) {
    super.text ??= 'Type here.';
  }

  @override
  State<NoteBlock> createState() => _NoteBlockState();
}

class _NoteBlockState extends State<NoteBlock> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    // TODO: implement dispose
    widget.text = _controller.text;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Note'),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
              padding: const EdgeInsets.symmetric(vertical: 4),
              width: 220,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CustomIconButton(
                    icon: Icons.delete,
                    iconSize: 15,
                    innerColor: color.onError,
                    iconColor: color.error,
                    onPressed: () {
                      widget.delete!(widget.id);
                    },
                  ),
                  CustomIconButton(
                    icon: Icons.arrow_upward,
                    iconSize: 15,
                    onPressed: () {
                      widget.moveUp!(widget.id);
                    },
                  ),
                  CustomIconButton(
                    icon: Icons.arrow_downward,
                    iconSize: 15,
                    onPressed: () {
                      widget.moveDown!(widget.id);
                    },
                  )
                ],
              ),
            )
          ],
        ),
        Container(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.text,
              border: InputBorder.none,
              hintStyle: textTheme.bodyLarge!.copyWith(color: color.onSurface),
            ),
            style: textTheme.bodyLarge!.copyWith(color: color.onSurface),
            minLines: 1,
            maxLines: 1000,
            keyboardType: TextInputType.multiline,
          ),
        ),
      ],
    );
  }
}
