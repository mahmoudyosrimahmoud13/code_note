import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';
import '../../core/util/note_share_helper.dart';
import '../../features/notes/domain/entities/language.dart';

class NoteBlock extends Block {
  const NoteBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
  });

  @override
  State<NoteBlock> createState() => _NoteBlockState();
}

class _NoteBlockState extends State<NoteBlock> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void dispose() {
    // Note: In a real app, we'd update the entity via a callback/bloc
    // but to keep it simple and feature-parity, we'll assume it's updated.
    _controller.dispose();
    super.dispose();
  }

  void _shareNoteBlock() {
    NoteShareHelper.shareBlockAsFile(
      widget.entity,
      'Text Block',
      Language.none,
    );
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
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CustomIconButton(
                    icon: Icons.share,
                    iconSize: 15,
                    onPressed: _shareNoteBlock,
                  ),
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
        TextField(
          controller: _controller,
          onChanged: (val) {
            if (widget.onChanged != null) {
              widget.onChanged!(widget.entity.copyWith(text: val));
            }
          },
          decoration: InputDecoration(
            hintText: 'Type here.',
            border: InputBorder.none,
            hintStyle: textTheme.bodyLarge!.copyWith(color: color.onSurface),
          ),
          style: textTheme.bodyLarge!.copyWith(color: color.onSurface),
          minLines: 1,
          maxLines: 1000,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }
}
