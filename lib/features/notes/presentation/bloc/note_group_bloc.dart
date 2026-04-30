import '../../domain/entities/note_group.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/note_repository.dart';
import 'note_group_event.dart';
import 'note_group_state.dart';

class NoteGroupBloc extends Bloc<NoteGroupEvent, NoteGroupState> {
  final NoteRepository repository;

  NoteGroupBloc({required this.repository}) : super(NoteGroupInitial()) {
    on<GetGroupsEvent>((event, emit) async {
      emit(NoteGroupLoading());
      await emit.forEach<List<NoteGroupEntity>>(
        repository.watchGroups(),
        onData: (groups) => NoteGroupLoaded(groups),
        onError: (error, stackTrace) =>
            const NoteGroupError('Could not fetch groups'),
      );
    });

    on<AddGroupEvent>((event, emit) async {
      final result = await repository.addGroup(event.group);
      result.fold(
        (failure) => emit(const NoteGroupError('Could not add group')),
        (_) => add(GetGroupsEvent()),
      );
    });

    on<UpdateGroupEvent>((event, emit) async {
      final result = await repository.updateGroup(event.group);
      result.fold(
        (failure) => emit(const NoteGroupError('Could not update group')),
        (_) => add(GetGroupsEvent()),
      );
    });

    on<DeleteGroupEvent>((event, emit) async {
      final result = await repository.deleteGroup(event.id);
      result.fold(
        (failure) => emit(const NoteGroupError('Could not delete group')),
        (_) => add(GetGroupsEvent()),
      );
    });

    on<RemoveNoteFromAllGroupsEvent>((event, emit) async {
      final currentState = state;
      if (currentState is NoteGroupLoaded) {
        for (final group in currentState.groups) {
          if (group.noteIds.contains(event.noteId)) {
            final newNoteIds = List<String>.from(group.noteIds)
              ..remove(event.noteId);
            await repository.updateGroup(group.copyWith(noteIds: newNoteIds));
          }
        }
        add(GetGroupsEvent());
      }
    });
  }
}
