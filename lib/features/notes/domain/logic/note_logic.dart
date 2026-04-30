import '../entities/note.dart';

class NoteLogic {
  /// Event: Move Note to Trash
  /// Logic: When a note is moved to the trash, set isTrashed = true.
  /// Reset actions: It immediately loses its pinned status and is removed from its group.
  static NoteEntity moveToTrash(NoteEntity note) {
    return note.copyWith(
      isTrashed: true,
      isPinned: false,
      clearGroupId: true,
    );
  }

  /// Event: Unarchive (Restore) Note
  /// Logic: When a note is unarchived, set isArchived = false.
  /// Reset actions: It immediately loses its pinned status and is removed from its group.
  static NoteEntity restoreFromArchive(NoteEntity note) {
    return note.copyWith(
      isArchived: false,
      isPinned: false,
      clearGroupId: true,
    );
  }

  /// Event: Delete Group
  /// Logic: When a group is deleted, iterate through all notes that belonged to that group.
  /// Reset actions: Automatically apply the "Move Note to Trash" logic to every note inside that group.
  static List<NoteEntity> handleGroupDeletion(String groupId, List<NoteEntity> allNotes) {
    return allNotes.map((note) {
      if (note.groupId == groupId) {
        return moveToTrash(note);
      }
      return note;
    }).toList();
  }
}
