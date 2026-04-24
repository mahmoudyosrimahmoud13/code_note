import 'package:code_note/features/notes/domain/entities/note_group.dart';

class NoteGroupModel extends NoteGroupEntity {
  const NoteGroupModel({
    required super.id,
    required super.name,
    required super.noteIds,
    required super.lastModified,
  });

  factory NoteGroupModel.fromJson(Map<String, dynamic> json) {
    return NoteGroupModel(
      id: json['id'],
      name: json['name'],
      noteIds: List<String>.from(json['noteIds']),
      lastModified: DateTime.parse(json['lastModified']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'noteIds': noteIds,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory NoteGroupModel.fromEntity(NoteGroupEntity entity) {
    return NoteGroupModel(
      id: entity.id,
      name: entity.name,
      noteIds: entity.noteIds,
      lastModified: entity.lastModified,
    );
  }
}
