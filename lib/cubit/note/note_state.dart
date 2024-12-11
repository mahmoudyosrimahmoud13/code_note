part of 'note_cubit.dart';

@immutable
sealed class NoteState {}

final class NoteInitial extends NoteState {}

final class NoteLoading extends NoteState {}

final class NoteSuccess extends NoteState {
  void addNote(Note note) {
    notes
        .add(Note(id: uuid.generate(), lastModified: DateTime.now(), tags: []));
    print(notes);
  }

  void notesUpdate() {}
}

final class NoteError extends NoteState {
  final String error;

  NoteError({required this.error});
}
