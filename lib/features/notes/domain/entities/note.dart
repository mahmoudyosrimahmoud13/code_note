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
  final bool isTrashed;
  final String? groupId;
  final NoteReminderEntity? reminder;
  final int version;
  final DateTime? lastSyncedAt;
  final bool isDirty;
  final DateTime? trashTimestamp;

  const NoteEntity({
    required this.id,
    required this.title,
    required this.tags,
    required this.lastModified,
    required this.blocks,
    this.isPinned = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.groupId,
    this.reminder,
    this.version = 0,
    this.lastSyncedAt,
    this.isDirty = false,
    this.trashTimestamp,
  });

  NoteEntity copyWith({
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
    return NoteEntity(
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

  @override
  List<Object?> get props => [
        id,
        title,
        tags,
        lastModified,
        blocks,
        isPinned,
        isArchived,
        isTrashed,
        groupId,
        reminder,
        version,
        lastSyncedAt,
        isDirty,
        trashTimestamp,
      ];
}

class NoteReminderEntity extends Equatable {
  final DateTime dateTime;
  final String message;

  const NoteReminderEntity({
    required this.dateTime,
    required this.message,
  });

  @override
  List<Object?> get props => [dateTime, message];
}
