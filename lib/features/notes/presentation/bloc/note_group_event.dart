import 'package:equatable/equatable.dart';

import '../../domain/entities/note_group.dart';

abstract class NoteGroupEvent extends Equatable {
  const NoteGroupEvent();

  @override
  List<Object> get props => [];
}

/// Start listening to stored groups. Safe to send more than once.
class GetGroupsEvent extends NoteGroupEvent {}

/// Sent by the bloc itself when storage changes.
class GroupsChangedEvent extends NoteGroupEvent {
  final List<NoteGroupEntity> groups;
  const GroupsChangedEvent(this.groups);

  @override
  List<Object> get props => [groups];
}

class AddGroupEvent extends NoteGroupEvent {
  final NoteGroupEntity group;
  const AddGroupEvent(this.group);

  @override
  List<Object> get props => [group];
}

class UpdateGroupEvent extends NoteGroupEvent {
  final NoteGroupEntity group;
  const UpdateGroupEvent(this.group);

  @override
  List<Object> get props => [group];
}

class DeleteGroupEvent extends NoteGroupEvent {
  final String id;
  const DeleteGroupEvent(this.id);

  @override
  List<Object> get props => [id];
}

class RemoveNoteFromAllGroupsEvent extends NoteGroupEvent {
  final String noteId;
  const RemoveNoteFromAllGroupsEvent(this.noteId);

  @override
  List<Object> get props => [noteId];
}
