import 'package:equatable/equatable.dart';
import '../../domain/entities/note.dart';

abstract class NoteEvent extends Equatable {
  const NoteEvent();

  @override
  List<Object> get props => [];
}

/// Start listening to stored notes. Safe to send more than once.
class GetNotesEvent extends NoteEvent {}

/// Sent by the bloc itself when storage changes.
class NotesChangedEvent extends NoteEvent {
  final List<NoteEntity> notes;

  const NotesChangedEvent(this.notes);

  @override
  List<Object> get props => [notes];
}

class AddNoteEvent extends NoteEvent {
  final NoteEntity note;

  const AddNoteEvent(this.note);

  @override
  List<Object> get props => [note];
}

class UpdateNoteEvent extends NoteEvent {
  final NoteEntity note;

  const UpdateNoteEvent(this.note);

  @override
  List<Object> get props => [note];
}

/// Deletes a note for good (used from the trash).
class DeleteNoteEvent extends NoteEvent {
  final String id;

  const DeleteNoteEvent(this.id);

  @override
  List<Object> get props => [id];
}

/// Deletes notes that sat in the trash longer than 30 days.
class PurgeOldTrashEvent extends NoteEvent {}
