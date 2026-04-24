import 'package:equatable/equatable.dart';

class NoteGroupEntity extends Equatable {
  final String id;
  final String name;
  final List<String> noteIds;
  final DateTime lastModified;

  const NoteGroupEntity({
    required this.id,
    required this.name,
    required this.noteIds,
    required this.lastModified,
  });

  NoteGroupEntity copyWith({
    String? id,
    String? name,
    List<String>? noteIds,
    DateTime? lastModified,
  }) {
    return NoteGroupEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      noteIds: noteIds ?? this.noteIds,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  @override
  List<Object?> get props => [id, name, noteIds, lastModified];
}
