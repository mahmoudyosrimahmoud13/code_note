import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/get_notes.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/entities/block.dart';
import 'note_event.dart';
import 'note_state.dart';

class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final GetNotes getNotes;
  final NoteRepository repository;

  NoteBloc({
    required this.getNotes,
    required this.repository,
  }) : super(NoteInitial()) {
    on<GetNotesEvent>((event, emit) async {
      emit(NoteLoading());
      final result = await getNotes(NoParams());
      result.fold(
        (failure) => emit(const NoteError('Could not fetch notes')),
        (notes) => emit(NoteLoaded(notes)),
      );
    });

    on<AddNoteEvent>((event, emit) async {
      final result = await repository.addNote(event.note);
      result.fold(
        (failure) => emit(const NoteError('Could not add note')),
        (_) => add(GetNotesEvent()),
      );
    });

    on<UpdateNoteEvent>((event, emit) async {
      final currentState = state;
      if (currentState is NoteLoaded) {
        final updatedNotes = currentState.notes.map((n) => n.id == event.note.id ? event.note : n).toList();
        emit(NoteLoaded(updatedNotes));
      }
      
      final result = await repository.updateNote(event.note);
      result.fold(
        (failure) {
          emit(const NoteError('Could not update note'));
          add(GetNotesEvent()); // Revert on failure
        },
        (_) => null, // Already updated locally
      );
    });

    on<DeleteNoteEvent>((event, emit) async {
      final currentState = state;
      if (currentState is NoteLoaded) {
        final updatedNotes = currentState.notes.where((n) => n.id != event.id).toList();
        emit(NoteLoaded(updatedNotes));
      }

      final result = await repository.deleteNote(event.id);
      result.fold(
        (failure) {
          emit(const NoteError('Could not delete note'));
          add(GetNotesEvent()); // Revert on failure
        },
        (_) => null, // Already updated locally
      );
    });
    on<SearchNotesEvent>((event, emit) async {
      if (event.query.isEmpty) {
        add(GetNotesEvent());
        return;
      }

      final result = await getNotes(NoParams());
      result.fold(
        (failure) => emit(const NoteError('Could not fetch notes for search')),
        (notes) {
          final query = event.query.toLowerCase();
          final filteredNotes = notes.where((note) {
            final titleMatch = note.title.toLowerCase().contains(query);
            final tagMatch = note.tags.any((tag) => tag.toLowerCase().contains(query));
            final contentMatch = note.blocks.any((block) {
              if (block is NoteBlockEntity) {
                return block.text?.toLowerCase().contains(query) ?? false;
              } else if (block is CodeBlockEntity) {
                return block.text?.toLowerCase().contains(query) ?? false;
              }
              return false;
            });
            return titleMatch || tagMatch || contentMatch;
          }).toList();
          emit(NoteLoaded(filteredNotes));
        },
      );
    });
  }
}
