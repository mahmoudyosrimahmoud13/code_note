import 'package:flutter_test/flutter_test.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/logic/note_logic.dart';

void main() {
  group('NoteLogic Business Rules Tests', () {
    final now = DateTime.now();
    
    final testNote = NoteEntity(
      id: 'note-1',
      title: 'Pinned Grouped Note',
      tags: const ['test'],
      lastModified: now,
      blocks: const [],
      isPinned: true,
      isArchived: false,
      isTrashed: false,
      groupId: 'group-A',
    );

    test('RULE 1: A pinned, grouped note moving to trash (asserting it loses pin and group)', () {
      // Act
      final result = NoteLogic.moveToTrash(testNote);

      // Assert
      expect(result.isTrashed, true, reason: 'Note should be marked as trashed');
      expect(result.isPinned, false, reason: 'Note should lose its pinned status');
      expect(result.groupId, isNull, reason: 'Note should be removed from its group');
    });

    test('RULE 2: A pinned, grouped note being unarchived (asserting it loses pin and group)', () {
      final archivedNote = testNote.copyWith(isArchived: true);
      
      // Act
      final result = NoteLogic.restoreFromArchive(archivedNote);

      // Assert
      expect(result.isArchived, false, reason: 'Note should be unarchived');
      expect(result.isPinned, false, reason: 'Note should lose its pinned status upon unarchiving');
      expect(result.groupId, isNull, reason: 'Note should be removed from its group upon unarchiving');
    });

    test('RULE 3: A group deletion (asserting all its child notes are moved to trash, unpinned, and ungrouped, while notes outside the group remain unaffected)', () {
      final noteInGroup1 = testNote.copyWith(id: 'note-1', groupId: 'group-A');
      final noteInGroup2 = testNote.copyWith(id: 'note-2', groupId: 'group-A');
      final noteOutsideGroup = testNote.copyWith(id: 'note-3', groupId: 'group-B', isPinned: true);
      
      final allNotes = [noteInGroup1, noteInGroup2, noteOutsideGroup];

      // Act
      final resultList = NoteLogic.handleGroupDeletion('group-A', allNotes);

      // Assert
      final updatedNote1 = resultList.firstWhere((n) => n.id == 'note-1');
      final updatedNote2 = resultList.firstWhere((n) => n.id == 'note-2');
      final updatedNote3 = resultList.firstWhere((n) => n.id == 'note-3');

      // Check notes that were in group A
      expect(updatedNote1.isTrashed, true);
      expect(updatedNote1.isPinned, false);
      expect(updatedNote1.groupId, isNull);

      expect(updatedNote2.isTrashed, true);
      expect(updatedNote2.isPinned, false);
      expect(updatedNote2.groupId, isNull);

      // Check note outside group A (should remain unaffected)
      expect(updatedNote3.isTrashed, false);
      expect(updatedNote3.isPinned, true);
      expect(updatedNote3.groupId, 'group-B');
    });
  });
}
