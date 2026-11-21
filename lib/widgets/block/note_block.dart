import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/util/note_share_helper.dart';
import '../../features/links/link_widgets.dart';
import '../../features/notes/domain/entities/language.dart';
import 'block.dart';
import 'block_frame.dart';

/// A plain text block. Links in it are highlighted, and get a preview
/// card (picture, title, site) under the text.
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
  late final LinkTextController _controller;

  /// The text the previews are made from. It follows the field a moment
  /// after typing stops, so half-typed links aren't fetched.
  late String _settled;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    _controller = LinkTextController(text: widget.text);
    _settled = widget.text ?? '';
  }

  @override
  void dispose() {
    _settle?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String val) {
    widget.onChanged?.call(widget.entity.copyWith(text: val));
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _settled != _controller.text) setState(() => _settled = _controller.text);
    });
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
            onChanged: _changed,
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
          LinkPreviewList(text: _settled),
        ],
      ),
    );
  }
}
