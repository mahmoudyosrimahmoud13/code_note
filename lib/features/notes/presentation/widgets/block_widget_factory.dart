import 'package:flutter/material.dart';
import '../../domain/entities/block.dart';
import '../../../../widgets/block/note_block.dart';
import '../../../../widgets/block/code_block.dart';
import '../../../../widgets/block/image_block.dart';

class BlockWidgetFactory {
  static Widget createBlockWidget({
    required BlockEntity entity,
    void Function(String id)? onDelete,
    void Function(String id)? onMoveUp,
    void Function(String id)? onMoveDown,
    void Function(BlockEntity entity)? onChanged,
  }) {
    if (entity is NoteBlockEntity) {
      return NoteBlock(
        key: ValueKey(entity.id),
        entity: entity,
        delete: onDelete,
        moveUp: onMoveUp,
        moveDown: onMoveDown,
        onChanged: onChanged,
      );
    } else if (entity is CodeBlockEntity) {
      return CodeBlock(
        key: ValueKey(entity.id),
        entity: entity,
        delete: onDelete,
        moveUp: onMoveUp,
        moveDown: onMoveDown,
        onChanged: onChanged,
      );
    } else if (entity is ImageBlockEntity) {
      return ImageBlock(
        key: ValueKey(entity.id),
        entity: entity,
        delete: onDelete,
        moveUp: onMoveUp,
        moveDown: onMoveDown,
        onChanged: onChanged,
      );
    }
    return const SizedBox.shrink();
  }
}
