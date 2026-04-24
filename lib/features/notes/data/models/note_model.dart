import '../../domain/entities/note.dart';
import '../../domain/entities/block.dart';
import 'block_model.dart';

class NoteModel extends NoteEntity {
  const NoteModel({
    required super.id,
    required super.title,
    required super.tags,
    required super.lastModified,
    required super.blocks,
    super.isPinned,
    super.isArchived,
    super.isDeleted,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'],
      title: json['title'],
      tags: List<String>.from(json['tags']),
      lastModified: DateTime.parse(json['lastModified']),
      blocks: (json['blocks'] as List)
          .map((i) => BlockModel.fromJson(i).toEntity())
          .toList(),
      isPinned: json['isPinned'] ?? false,
      isArchived: json['isArchived'] ?? false,
      isDeleted: json['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'tags': tags,
      'lastModified': lastModified.toIso8601String(),
      'blocks': blocks.map((i) => BlockModel.fromEntity(i).toJson()).toList(),
      'isPinned': isPinned,
      'isArchived': isArchived,
      'isDeleted': isDeleted,
    };
  }

  @override
  NoteModel copyWith({
    String? id,
    String? title,
    List<String>? tags,
    DateTime? lastModified,
    List<BlockEntity>? blocks,
    bool? isPinned,
    bool? isArchived,
    bool? isDeleted,
  }) {
    return NoteModel(
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
}
