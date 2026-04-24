import '../../domain/entities/note.dart';
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
    super.reminder,
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
      reminder: json['reminder'] != null 
          ? NoteReminderModel.fromJson(json['reminder']) 
          : null,
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
      'reminder': reminder != null 
          ? NoteReminderModel.fromEntity(reminder!).toJson() 
          : null,
    };
  }

  static NoteModel fromEntity(NoteEntity entity) {
    return NoteModel(
      id: entity.id,
      title: entity.title,
      tags: entity.tags,
      lastModified: entity.lastModified,
      blocks: entity.blocks,
      isPinned: entity.isPinned,
      isArchived: entity.isArchived,
      isDeleted: entity.isDeleted,
      reminder: entity.reminder,
    );
  }
}

class NoteReminderModel extends NoteReminderEntity {
  const NoteReminderModel({
    required super.dateTime,
    required super.message,
  });

  factory NoteReminderModel.fromJson(Map<String, dynamic> json) {
    return NoteReminderModel(
      dateTime: DateTime.parse(json['dateTime']),
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dateTime': dateTime.toIso8601String(),
      'message': message,
    };
  }

  factory NoteReminderModel.fromEntity(NoteReminderEntity entity) {
    return NoteReminderModel(
      dateTime: entity.dateTime,
      message: entity.message,
    );
  }
}
