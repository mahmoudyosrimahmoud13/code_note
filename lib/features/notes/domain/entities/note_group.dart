import 'package:equatable/equatable.dart';

import 'run_plan.dart';

class NoteGroupEntity extends Equatable {
  final String id;
  final String name;
  final List<String> noteIds;
  final DateTime lastModified;

  /// How ▶ Run folder runs this folder's notes. Null: folder order, last
  /// runnable note as the primary.
  final RunPlan? runPlan;

  const NoteGroupEntity({
    required this.id,
    required this.name,
    required this.noteIds,
    required this.lastModified,
    this.runPlan,
  });

  NoteGroupEntity copyWith({
    String? id,
    String? name,
    List<String>? noteIds,
    DateTime? lastModified,
    RunPlan? runPlan,
  }) {
    return NoteGroupEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      noteIds: noteIds ?? this.noteIds,
      lastModified: lastModified ?? this.lastModified,
      runPlan: runPlan ?? this.runPlan,
    );
  }

  @override
  List<Object?> get props => [id, name, noteIds, lastModified, runPlan];
}
