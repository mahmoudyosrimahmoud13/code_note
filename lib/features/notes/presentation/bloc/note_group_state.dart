import 'package:equatable/equatable.dart';
import '../../domain/entities/note_group.dart';

abstract class NoteGroupState extends Equatable {
  const NoteGroupState();

  @override
  List<Object> get props => [];
}

class NoteGroupInitial extends NoteGroupState {}

class NoteGroupLoading extends NoteGroupState {}

class NoteGroupLoaded extends NoteGroupState {
  final List<NoteGroupEntity> groups;
  const NoteGroupLoaded(this.groups);

  @override
  List<Object> get props => [groups];
}

class NoteGroupError extends NoteGroupState {
  final String message;
  const NoteGroupError(this.message);

  @override
  List<Object> get props => [message];
}
