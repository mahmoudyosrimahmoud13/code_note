import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/widgets/note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class HomeGridView extends StatelessWidget {
  const HomeGridView({
    super.key,
    required this.notes,
    this.isShrinkWrap = false,
    this.isTrashView = false,
    this.onNoteTap,
    this.onRemoveFromGroup,
    this.onNoteDismissed,
  });

  final List<NoteEntity> notes;
  final bool isShrinkWrap;
  final bool isTrashView;
  final void Function(NoteEntity note)? onNoteTap;
  final void Function(NoteEntity note)? onRemoveFromGroup;
  final void Function(NoteEntity note)? onNoteDismissed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth > 1200) {
          crossAxisCount = 6;
        } else if (constraints.maxWidth > 900) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth > 600) {
          crossAxisCount = 3;
        } else if (constraints.maxWidth < 350) {
          crossAxisCount = 1;
        }
        
        return MasonryGridView.builder(
          key: ValueKey('grid_${notes.length}_${notes.isNotEmpty ? notes.first.id : "empty"}'),
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
          ),
          itemCount: notes.length,
          padding: const EdgeInsets.all(8),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: isShrinkWrap,
          physics: isShrinkWrap ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final note = notes[index];
            return NoteCard(
              key: ValueKey('note_card_${note.id}'),
              note: note, 
              isTrashView: isTrashView,
              onTapOverride: onNoteTap != null ? () => onNoteTap!(note) : null,
              onRemoveFromGroup: onRemoveFromGroup != null ? () => onRemoveFromGroup!(note) : null,
              onDismissed: onNoteDismissed != null ? () => onNoteDismissed!(note) : null,
            );
          },
        );
      },
    );
  }
}
