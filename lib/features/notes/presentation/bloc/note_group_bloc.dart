import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/note_group.dart';
import '../../domain/repositories/note_repository.dart';
import 'note_group_event.dart';
import 'note_group_state.dart';

/// Holds every group. Like NoteBloc, it listens to storage only once.
class NoteGroupBloc extends Bloc<NoteGroupEvent, NoteGroupState> {
  final NoteRepository repository;
  StreamSubscription<List<NoteGroupEntity>>? _subscription;

  NoteGroupBloc({required this.repository}) : super(NoteGroupInitial()) {
    on<GetGroupsEvent>((event, emit) {
      if (_subscription != null) return;
      if (state is! NoteGroupLoaded) emit(NoteGroupLoading());
      _subscription = repository.watchGroups().listen(
            (groups) => add(GroupsChangedEvent(groups)),
            onError: (_) => add(const GroupsChangedEvent([])),
          );
    });

    on<GroupsChangedEvent>((event, emit) {
      final sorted = List<NoteGroupEntity>.of(event.groups)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      emit(NoteGroupLoaded(sorted));
    });

    on<AddGroupEvent>((event, emit) async {
      await repository.addGroup(event.group);
    });
    on<UpdateGroupEvent>((event, emit) async {
      await repository.updateGroup(event.group);
    });
    on<DeleteGroupEvent>((event, emit) async {
      await repository.deleteGroup(event.id);
    });

    on<RemoveNoteFromAllGroupsEvent>((event, emit) async {
      final current = state;
      if (current is! NoteGroupLoaded) return;
      for (final group in current.groups) {
        if (group.noteIds.contains(event.noteId)) {
          await repository.updateGroup(group.copyWith(
            noteIds: group.noteIds.where((id) => id != event.noteId).toList(),
          ));
        }
      }
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
