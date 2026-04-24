import 'package:equatable/equatable.dart';
import 'block.dart';

class NoteEntity extends Equatable {
  final String id;
  final String title;
  final List<String> tags;
  final DateTime lastModified;
  final List<BlockEntity> blocks;
  final bool isPinned;
  final bool isArchived;
  final bool isDeleted;

  const NoteEntity({
    required this.id,
    required this.title,
    required this.tags,
    required this.lastModified,
    required this.blocks,
    this.isPinned = false,
    this.isArchived = false,
    this.isDeleted = false,
  });

  NoteEntity copyWith({
    String? id,
    String? title,
    List<String>? tags,
    DateTime? lastModified,
    List<BlockEntity>? blocks,
    bool? isPinned,
    bool? isArchived,
    bool? isDeleted,
  }) {
    return NoteEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      lastModified: lastModified ?? this.lastModified,
      blocks: blocks ?? this.blocks,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  List<Object?> get props => [id, title, tags, lastModified, blocks, isPinned, isArchived, isDeleted];
}
