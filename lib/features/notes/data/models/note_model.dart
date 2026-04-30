import '../../domain/entities/block.dart';
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
    super.isTrashed,
    super.groupId,
    super.reminder,
    super.version,
    super.lastSyncedAt,
    super.isDirty,
    super.trashTimestamp,
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
      isTrashed: json['isTrashed'] ?? false,
      groupId: json['groupId'],
      reminder: json['reminder'] != null
          ? NoteReminderModel.fromJson(json['reminder'])
          : null,
      version: json['version'] ?? 0,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'])
          : null,
      isDirty: json['isDirty'] ?? false,
      trashTimestamp: json['trashTimestamp'] != null
          ? DateTime.parse(json['trashTimestamp'])
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
      'isTrashed': isTrashed,
      'groupId': groupId,
      'reminder': reminder != null
          ? NoteReminderModel.fromEntity(reminder!).toJson()
          : null,
      'version': version,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'isDirty': isDirty,
      'trashTimestamp': trashTimestamp?.toIso8601String(),
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
      isTrashed: entity.isTrashed,
      groupId: entity.groupId,
      reminder: entity.reminder,
      version: entity.version,
      lastSyncedAt: entity.lastSyncedAt,
      isDirty: entity.isDirty,
      trashTimestamp: entity.trashTimestamp,
    );
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
    bool? isTrashed,
    String? groupId,
    bool clearGroupId = false,
    NoteReminderEntity? reminder,
    bool clearReminder = false,
    int? version,
    DateTime? lastSyncedAt,
    bool? isDirty,
    DateTime? trashTimestamp,
    bool clearTrashTimestamp = false,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      lastModified: lastModified ?? this.lastModified,
      blocks: blocks ?? this.blocks,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      reminder: clearReminder ? null : (reminder ?? this.reminder),
      version: version ?? this.version,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isDirty: isDirty ?? this.isDirty,
      trashTimestamp:
          clearTrashTimestamp ? null : (trashTimestamp ?? this.trashTimestamp),
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
