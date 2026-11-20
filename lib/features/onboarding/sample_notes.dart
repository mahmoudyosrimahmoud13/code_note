import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import '../notes/presentation/bloc/note_bloc.dart';
import '../notes/presentation/bloc/note_event.dart';
import '../notes/presentation/bloc/note_group_bloc.dart';
import '../notes/presentation/bloc/note_group_event.dart';
import '../notes/presentation/bloc/note_group_state.dart';
import '../notes/presentation/bloc/note_state.dart';
import 'demo_content.dart';

/// Adds the sample notes and folders from [DemoContent].
///
/// Notes whose title already exists are skipped, so pressing it twice never
/// makes copies. A folder with the same name as an existing one gets the new
/// notes added to it instead of a second folder.
///
/// With [onlyIfEmpty], nothing is added when there are already notes
/// (first launch after an update from an older version).
///
/// Returns how many notes were added.
int addSampleNotes(BuildContext context, {bool onlyIfEmpty = false}) {
  final noteBloc = context.read<NoteBloc>();
  final groupBloc = context.read<NoteGroupBloc>();
  final noteState = noteBloc.state;
  final existing = noteState is NoteLoaded ? noteState.notes : const <NoteEntity>[];
  if (onlyIfEmpty && existing.isNotEmpty) return 0;

  final takenTitles = {
    for (final n in existing)
      if (!n.isTrashed) n.title.trim().toLowerCase(),
  };
  final demo = DemoContent.build();
  final added = [
    for (final n in demo.notes)
      if (!takenTitles.contains(n.title.trim().toLowerCase())) n,
  ];
  for (final note in added) {
    noteBloc.add(AddNoteEvent(note));
  }

  final addedIds = {for (final n in added) n.id};
  final groupState = groupBloc.state;
  final groups = groupState is NoteGroupLoaded ? groupState.groups : const <NoteGroupEntity>[];
  for (final group in demo.groups) {
    final ids = group.noteIds.where(addedIds.contains).toList();
    if (ids.isEmpty) continue;
    final same = groups.where((g) => g.name == group.name);
    if (same.isEmpty) {
      groupBloc.add(AddGroupEvent(group.copyWith(noteIds: ids)));
    } else {
      final old = same.first;
      groupBloc.add(UpdateGroupEvent(old.copyWith(
        noteIds: [...old.noteIds, ...ids],
        lastModified: DateTime.now(),
      )));
    }
  }
  return added.length;
}
