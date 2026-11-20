import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../features/notes/domain/entities/note.dart';
import 'note_card.dart';

/// How many columns fit in [width]. Cards stay roughly 220 to 300 wide,
/// so a wide desktop window fills up instead of leaving empty space.
int noteColumnsFor(double width) {
  if (width < 360) return 1;
  return (width / 260).floor().clamp(2, 8);
}

Widget _card(
  NoteEntity note, {
  required bool isTrashView,
  void Function(NoteEntity note)? onNoteTap,
  void Function(NoteEntity note)? onRemoveFromGroup,
  void Function(NoteEntity note)? onNoteDismissed,
}) {
  return NoteCard(
    key: ValueKey('note_card_${note.id}'),
    note: note,
    isTrashView: isTrashView,
    onTapOverride: onNoteTap == null ? null : () => onNoteTap(note),
    onRemoveFromGroup:
        onRemoveFromGroup == null ? null : () => onRemoveFromGroup(note),
    onDismissed: onNoteDismissed == null ? null : () => onNoteDismissed(note),
  );
}

/// A scrolling grid of notes (used on the group page).
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
      builder: (context, constraints) => MasonryGridView.count(
        crossAxisCount: noteColumnsFor(constraints.maxWidth),
        itemCount: notes.length,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        shrinkWrap: isShrinkWrap,
        physics: isShrinkWrap ? const NeverScrollableScrollPhysics() : null,
        itemBuilder: (context, index) => _card(
          notes[index],
          isTrashView: isTrashView,
          onNoteTap: onNoteTap,
          onRemoveFromGroup: onRemoveFromGroup,
          onNoteDismissed: onNoteDismissed,
        ),
      ),
    );
  }
}

/// The same grid as a sliver, for pages that scroll several sections
/// together. Only the cards on screen are built, which keeps long lists fast.
class NotesSliverGrid extends StatelessWidget {
  const NotesSliverGrid({
    super.key,
    required this.notes,
    this.isTrashView = false,
    this.onNoteDismissed,
  });

  final List<NoteEntity> notes;
  final bool isTrashView;
  final void Function(NoteEntity note)? onNoteDismissed;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverMasonryGrid.count(
          crossAxisCount: noteColumnsFor(constraints.crossAxisExtent - 32),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childCount: notes.length,
          itemBuilder: (context, index) => _card(
            notes[index],
            isTrashView: isTrashView,
            onNoteDismissed: onNoteDismissed,
          ),
        ),
      ),
    );
  }
}
