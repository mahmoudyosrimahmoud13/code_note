import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/log_service.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/usecases/get_notes.dart';
import 'note_event.dart';
import 'note_state.dart';

/// Holds every note. Screens filter what they show themselves.
///
/// The bloc listens to storage exactly once. Asking for notes again
/// ([GetNotesEvent]) never opens a second listener, which is what used to
/// make the app slower the longer it ran.
class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final GetNotes getNotes;
  final NoteRepository repository;

  StreamSubscription<List<NoteEntity>>? _subscription;

  NoteBloc({
    required this.getNotes,
    required this.repository,
  }) : super(NoteInitial()) {
    on<GetNotesEvent>(_onGetNotes);
    on<NotesChangedEvent>((event, emit) => emit(NoteLoaded(event.notes)));
    on<AddNoteEvent>(_onSave);
    on<UpdateNoteEvent>(_onSave);
    on<DeleteNoteEvent>(_onDelete);
    on<PurgeOldTrashEvent>((event, emit) async {
      await repository.purgeOldTrash();
    });
  }

  void _onGetNotes(GetNotesEvent event, Emitter<NoteState> emit) {
    if (_subscription != null) return;
    if (state is! NoteLoaded) emit(NoteLoading());
    _subscription = repository.watchNotes().listen(
          (notes) => add(NotesChangedEvent(notes)),
          onError: (_) => add(const NotesChangedEvent([])),
        );
  }

  Future<void> _onSave(NoteEvent event, Emitter<NoteState> emit) async {
    final note = event is AddNoteEvent
        ? event.note
        : (event as UpdateNoteEvent).note;

    // Show the change right away; storage confirms it a moment later.
    final current = state;
    if (current is NoteLoaded) {
      final exists = current.notes.any((n) => n.id == note.id);
      emit(NoteLoaded(exists
          ? [for (final n in current.notes) n.id == note.id ? note : n]
          : [...current.notes, note]));
    }

    final result = await repository.updateNote(note);
    result.fold(
      (_) => LogService().log('NoteBloc: [ERROR] Could not save note ${note.id}'),
      (_) {},
    );
  }

  Future<void> _onDelete(DeleteNoteEvent event, Emitter<NoteState> emit) async {
    final current = state;
    if (current is NoteLoaded) {
      emit(NoteLoaded(current.notes.where((n) => n.id != event.id).toList()));
    }
    final result = await repository.deleteNote(event.id);
    result.fold(
      (_) => LogService().log('NoteBloc: [ERROR] Could not delete note ${event.id}'),
      (_) {},
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
