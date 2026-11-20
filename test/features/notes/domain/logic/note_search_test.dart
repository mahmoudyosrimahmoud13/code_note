import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/logic/note_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final note = NoteEntity(
    id: '1',
    title: 'Flutter tips',
    tags: const ['mobile'],
    lastModified: DateTime(2026),
    blocks: const [
      NoteBlockEntity(id: 't', text: 'Use const widgets'),
      CodeBlockEntity(id: 'c', text: 'void main() {}', language: Language.dart),
    ],
  );

  test('matches title, tags, text and code, ignoring case', () {
    expect(noteMatches(note, 'flutter'), isTrue);
    expect(noteMatches(note, '#mobile'), isTrue);
    expect(noteMatches(note, 'CONST'), isTrue);
    expect(noteMatches(note, 'main()'), isTrue);
    expect(noteMatches(note, '   '), isTrue);
  });

  test('does not match unrelated words', () {
    expect(noteMatches(note, 'python'), isFalse);
  });
}
