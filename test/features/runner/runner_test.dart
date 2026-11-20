import 'package:code_note/features/backup/backup_service.dart';
import 'package:code_note/features/notes/data/models/block_model.dart';
import 'package:code_note/features/notes/data/models/note_group_model.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/entities/run_plan.dart';
import 'package:code_note/features/runner/code_runner.dart';
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

  test('a note runs top to bottom, skips skipped blocks, primary last', () {
    const a = CodeBlockEntity(id: 'a', text: 'echo a', language: Language.bash);
    const b = CodeBlockEntity(id: 'b', text: 'echo b', language: Language.bash, runRole: RunRole.skip);
    const c = CodeBlockEntity(id: 'c', text: 'echo c', language: Language.bash, runRole: RunRole.main);
    const d = CodeBlockEntity(id: 'd', text: 'echo d', language: Language.bash, runRole: RunRole.background);
    const html = CodeBlockEntity(id: 'h', text: '<p>', language: Language.html);
    expect(RunManager.folderBlocks(note([a, b, html])).map((x) => x.id), ['a']);
    expect(RunManager.folderBlocks(note([c, a, b, d])).map((x) => x.id), ['a', 'd', 'c']);
  });

  test('JavaScript in a web page note belongs to the page, otherwise Node runs it', () {
    const js = CodeBlockEntity(id: 'j', text: 'console.log(1)', language: Language.javaScript);
    const html = CodeBlockEntity(id: 'h', text: '<p>hi</p>', language: Language.html);
    expect(CodeRunner.isWebPageNote([js, html]), isTrue);
    expect(CodeRunner.canRunIn(Language.javaScript, [js, html]), isFalse);
    expect(CodeRunner.canRunIn(Language.javaScript, [js]), CodeRunner.canRun(Language.javaScript));
    expect(RunManager.folderBlocks(note([js, html])), isEmpty);
  });

  test('run order: saved order, new notes added, primary always last', () {
    const plan = RunPlan(order: ['c', 'a'], primary: 'a', keepRunning: {'b'}, disabled: {'d'});
    final steps = plan.steps(['a', 'b', 'c', 'd']);
    expect(steps.map((s) => s.noteId), ['c', 'b', 'a']);
    expect(steps.last.primary, isTrue);
    expect(steps[1].wait, isFalse); // b keeps running
    expect(steps.first.wait, isTrue);
    // No plan: folder order, the last note is the primary.
    expect(const RunPlan().steps(['x', 'y']).map((s) => '$s'), ['x', 'y*']);
    // A disabled primary falls back to the last enabled note.
    expect(const RunPlan(primary: 'y', disabled: {'y'}).primaryFor(['x', 'y', 'z']), 'z');
  });

  test('the run order is saved with the folder, old folders have none', () {
    final group = NoteGroupModel(
      id: 'g', name: 'f', noteIds: const ['a', 'b'], lastModified: DateTime(2026),
      runPlan: const RunPlan(order: ['b', 'a'], primary: 'b', keepRunning: {'a'}),
    );
    final back = NoteGroupModel.fromJson(group.toJson());
    expect(back.runPlan, group.runPlan);
    final old = NoteGroupModel.fromJson({'id': 'g', 'name': 'f', 'noteIds': ['a'], 'lastModified': '2026-01-01T00:00:00.000'});
    expect(old.runPlan, isNull);
  });

  test('reads pip progress and npm output, keeps npm names safe', () {
    expect(Runtimes.pipProgress('Progress 512 of 1024'), 0.5);
    expect(Runtimes.pipProgress('Collecting yt-dlp'), isNull);
    final list = Runtimes.parseNpmList('{"dependencies":{"prettier":{"version":"3.3.0"},"npm":{"version":"10"}}}');
    expect(list.map((p) => p.name), ['prettier']);
    expect(Runtimes.parseNpmOutdated('{"prettier":{"current":"3.3.0","latest":"3.4.0"}}'), {'prettier': '3.4.0'});
    expect(Runtimes.cleanNpmName('@angular/cli@17'), '@angular/cli@17');
    expect(Runtimes.cleanNpmName('x; rm -rf /'), isNull);
  });

  test('shared .codenote files get a clean name', () {
    expect(BackupService.shareFileName('Snake: the game?'), 'Snake the game.codenote');
    expect(BackupService.shareFileName('  '), 'note.codenote');
  });
}
