import 'package:code_note/features/gist/gist_service.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseId', () {
    test('reads ids from links and bare ids', () {
      expect(GistService.parseId('https://gist.github.com/someone/aa5a315d61ae9438b18d'),
          'aa5a315d61ae9438b18d');
      expect(GistService.parseId('aa5a315d61ae9438b18d'), 'aa5a315d61ae9438b18d');
      expect(GistService.parseId('https://gist.github.com/someone/aa5a315d61ae9438b18d#file-a-py'),
          'aa5a315d61ae9438b18d');
    });
    test('rejects things that are not ids', () {
      expect(GistService.parseId(''), isNull);
      expect(GistService.parseId('hello world'), isNull);
    });
  });

  test('gist files become code blocks with the right language', () {
    final note = GistService.noteFromGistJson({
      'description': 'Handy snippets',
      'html_url': 'https://gist.github.com/x/1',
      'files': {
        'main.py': {'content': 'print(1)'},
        'README.md': {'content': '# Hi'},
      },
    });
    expect(note.title, 'Handy snippets');
    expect(note.tags, ['gist']);
    final code = note.blocks.whereType<CodeBlockEntity>().single;
    expect(code.language, Language.python);
    expect(note.blocks.whereType<MarkdownBlockEntity>().any((b) => b.text == '# Hi'), isTrue);
  });

  test('a note becomes one file per code block plus a README', () {
    final files = GistService.filesFromNote(NoteEntity(
      id: 'n',
      title: 'My Script!',
      tags: const [],
      lastModified: DateTime(2026),
      blocks: const [
        NoteBlockEntity(id: '1', text: 'Some words'),
        CodeBlockEntity(id: '2', language: Language.python, text: 'print(1)'),
        CodeBlockEntity(id: '3', language: Language.python, text: 'print(2)'),
        CodeBlockEntity(id: '4', language: Language.python, text: '   '),
      ],
    ));
    expect(files.keys, containsAll(['my-script.py', 'my-script-2.py', 'README.md']));
    expect(files.length, 3);
    expect(files['README.md'], contains('Some words'));
  });
}
