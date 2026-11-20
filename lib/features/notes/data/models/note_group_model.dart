import '../../domain/entities/note_group.dart';
import '../../domain/entities/run_plan.dart';

class NoteGroupModel extends NoteGroupEntity {
  const NoteGroupModel({
    required super.id,
    required super.name,
    required super.noteIds,
    required super.lastModified,
    super.runPlan,
  });

  factory NoteGroupModel.fromJson(Map<String, dynamic> json) {
    return NoteGroupModel(
      id: json['id'],
      name: json['name'],
      noteIds: List<String>.from(json['noteIds']),
      lastModified: DateTime.parse(json['lastModified']),
      runPlan: RunPlan.fromJson(json['runPlan']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'noteIds': noteIds,
      'lastModified': lastModified.toIso8601String(),
      if (runPlan != null) 'runPlan': runPlan!.toJson(),
    };
  }

  factory NoteGroupModel.fromEntity(NoteGroupEntity entity) {
    return NoteGroupModel(
      id: entity.id,
      name: entity.name,
      noteIds: entity.noteIds,
      lastModified: entity.lastModified,
      runPlan: entity.runPlan,
    );
  }
}
