part of 'note_cubit.dart';

@immutable
sealed class NoteState {}

final class NoteInitial extends NoteState {}

final class NoteLoading extends NoteState {}

final class NoteSuccess extends NoteState {
  final List<Note> notes;

  NoteSuccess({
    required this.notes,
  });
}

final class NoteError extends NoteState {
  final String error;

  NoteError({required this.error});
}
