import 'package:flutter/material.dart';

import '../../core/util/note_share_helper.dart';
import '../../features/notes/domain/entities/language.dart';
import 'block.dart';
import 'block_frame.dart';

/// A plain text block.
class NoteBlock extends Block {
  const NoteBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
    super.dragHandle,
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlockHeader(
              handle: widget.dragHandle,
            label: 'text',
            icon: Icons.notes_rounded,
            extraActions: [
              BlockAction(
                label: 'Share as file',
                icon: Icons.ios_share_rounded,
                onTap: () => NoteShareHelper.shareBlockAsFile(
                  widget.entity.copyWith(text: _controller.text),
                  'Text Block',
                  Language.none,
                ),
              ),
            ],
            onMoveUp: widget.moveUp == null ? null : () => widget.moveUp!(widget.id),
            onMoveDown:
                widget.moveDown == null ? null : () => widget.moveDown!(widget.id),
            onDelete: widget.delete == null ? null : () => widget.delete!(widget.id),
          ),
          TextField(
            controller: _controller,
            onChanged: (val) =>
                widget.onChanged?.call(widget.entity.copyWith(text: val)),
            decoration: InputDecoration(
              hintText: 'Write something…',
              filled: false,
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
              hintStyle: textTheme.bodyLarge!
                  .copyWith(color: color.onSurfaceVariant.withAlpha(150)),
            ),
            style: textTheme.bodyLarge!.copyWith(color: color.onSurface),
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.multiline,
          ),
        ],
      ),
    );
  }
}
