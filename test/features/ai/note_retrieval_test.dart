import 'package:code_note/features/ai/note_retrieval.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEntity note(String id, String title, String body,
        {List<String> tags = const [], bool trashed = false}) =>
    NoteEntity(
      id: id,
      title: title,
      tags: tags,
      lastModified: DateTime(2026, 1, 1),
      isTrashed: trashed,
      blocks: [CodeBlockEntity(id: '$id-b', language: Language.python, text: body)],
    );

void main() {
  final notes = [
    note('1', 'Docker volumes', 'docker run -v data:/data postgres', tags: ['docker']),
    note('2', 'Python venv', 'python -m venv .venv'),
    note('3', 'Old docker trick', 'docker system prune', trashed: true),
  ];

  test('drops filler words', () {
    expect(NoteRetrieval.words('How do I set up the docker volume?'),
        containsAll(['set', 'up', 'docker', 'volume']));
    expect(NoteRetrieval.words('what is the'), isEmpty);
  });

  test('finds the matching note first and skips the trash', () {
    final top = NoteRetrieval.topNotes(notes, 'docker volume setup');
    expect(top.first.id, '1');
    expect(top.any((n) => n.id == '3'), isFalse);
  });

  test('returns nothing when no note matches', () {
    expect(NoteRetrieval.topNotes(notes, 'kubernetes ingress'), isEmpty);
  });

  test('prompt numbers notes and ends with the question', () {
    final prompt = NoteRetrieval.buildPrompt('how?', [notes[0], notes[1]]);
    expect(prompt, contains('note [1]'));
    expect(prompt, contains('note [2]'));
    expect(prompt.trim().endsWith('Question: how?'), isTrue);
  });

  test('long notes are cut', () {
    final big = note('4', 'Big', 'x' * 10000);
    expect(NoteRetrieval.noteAsText(big, maxChars: 500).length, lessThan(520));
  });
}
