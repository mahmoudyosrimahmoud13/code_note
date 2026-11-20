import 'package:code_note/features/notes/data/models/block_model.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/runner/run_manager.dart';
import 'package:code_note/features/runner/runtimes.dart';
import 'package:code_note/features/runner/sandbox.dart';
import 'package:flutter_test/flutter_test.dart';

NoteEntity note(List<BlockEntity> blocks) =>
    NoteEntity(id: 'n', title: 'n', tags: const [], lastModified: DateTime(2026), blocks: blocks);

void main() {
  test('notes in one folder share a sandbox, other notes get their own', () {
    expect(Sandbox.keyFor(noteId: 'a', folderId: 'f'), Sandbox.keyFor(noteId: 'b', folderId: 'f'));
    expect(Sandbox.keyFor(noteId: 'a'), isNot(Sandbox.keyFor(noteId: 'b')));
  });

  test('picks the python-build-standalone file for this computer', () {
    final assets = [
      {'name': 'cpython-3.12.8+20250106-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz'},
      {'name': 'cpython-3.12.8+20250106-x86_64-unknown-linux-gnu-install_only.tar.gz'},
      {'name': 'cpython-3.13.1+20250106-x86_64-unknown-linux-gnu-install_only.tar.gz'},
      {'name': 'cpython-3.12.8+20250106-x86_64-pc-windows-msvc-install_only.tar.gz'},
    ];
    expect(Runtimes.pickPythonAsset(assets, 'x86_64-unknown-linux-gnu')!['name'],
        'cpython-3.12.8+20250106-x86_64-unknown-linux-gnu-install_only.tar.gz');
    expect(Runtimes.pickPythonAsset(assets, 'aarch64-unknown-linux-gnu'), isNull);
  });

  test('reads pip output and keeps package names safe', () {
    final list = Runtimes.parsePackages('[{"name":"yt-dlp","version":"1","latest_version":"2"},{"name":"Pip","version":"24"}]',
        outdated: true);
    expect(list.first.name, 'Pip');
    expect(list.last.outdated, isTrue);
    expect(Runtimes.cleanPackageName('yt-dlp'), 'yt-dlp');
    expect(Runtimes.cleanPackageName('numpy>=2.0'), 'numpy>=2.0');
    expect(Runtimes.cleanPackageName('x; rm -rf /'), isNull);
    expect(Runtimes.cleanPackageName('--index-url=http://evil'), isNull);
  });

  test('main and skip are saved with the note, old notes run normally', () {
    const block = CodeBlockEntity(id: 'b', text: 'x', language: Language.bash, runRole: RunRole.main);
    final json = BlockModel.fromEntity(block).toJson();
    final back = BlockModel.fromJson(json).toEntity() as CodeBlockEntity;
    expect(back.runRole, RunRole.main);
    final old = BlockModel.fromJson({'id': 'o', 'type': 'BlockType.code', 'text': 'x', 'language': 'Language.bash'});
    expect((old.toEntity() as CodeBlockEntity).runRole, RunRole.normal);
    expect(BlockModel.fromEntity(const CodeBlockEntity(id: 'n', language: Language.bash)).toJson().containsKey('runRole'), isFalse);
  });

  test('Run folder: a main block runs alone, skipped blocks never run', () {
    const a = CodeBlockEntity(id: 'a', text: 'echo a', language: Language.bash);
    const b = CodeBlockEntity(id: 'b', text: 'echo b', language: Language.bash, runRole: RunRole.skip);
    const c = CodeBlockEntity(id: 'c', text: 'echo c', language: Language.bash, runRole: RunRole.main);
    const html = CodeBlockEntity(id: 'h', text: '<p>', language: Language.html);
    expect(RunManager.folderBlocks(note([a, b, html])).map((x) => x.id), ['a']);
    expect(RunManager.folderBlocks(note([a, b, c])).map((x) => x.id), ['c']);
  });
}
