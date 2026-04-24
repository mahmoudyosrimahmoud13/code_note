import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/widgets/note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class HomeGridView extends StatelessWidget {
  const HomeGridView({super.key, required this.notes, this.isShrinkWrap = false, this.isTrashView = false});

  final List<NoteEntity> notes;
  final bool isShrinkWrap;
  final bool isTrashView;

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
        }
        
        return MasonryGridView.builder(
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
          ),
          itemCount: notes.length,
          padding: const EdgeInsets.all(8),
          shrinkWrap: isShrinkWrap,
          physics: isShrinkWrap ? const NeverScrollableScrollPhysics() : null,
          itemBuilder: (context, index) {
            final note = notes[index];
            return NoteCard(
              key: ValueKey(note.id),
              note: note, 
              isTrashView: isTrashView,
            );
          },
        );
      },
    );
  }
}
