import 'dart:io';
import 'dart:typed_data';

import 'package:code_note/features/backup/backup_service.dart';
import 'package:code_note/features/notes/data/datasources/note_local_data_source.dart';
import 'package:code_note/features/notes/data/repositories/note_repository_impl.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/entities/note_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('codenote_backup_test');
    Hive.init(dir.path);
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  Future<NoteRepositoryImpl> freshRepo() async {
    final box = await Hive.openBox('backup_${n++}');
    return NoteRepositoryImpl(localDataSource: NoteLocalDataSourceImpl(box: box));
  }

  NoteEntity note(String id, String title, DateTime at) => NoteEntity(
        id: id,
        title: title,
        tags: const ['t'],
        lastModified: at,
        blocks: [CodeBlockEntity(id: '$id-c', text: 'print("$id")', language: Language.rust)],
      );

  test('a backup restores every note and folder into an empty app', () async {
    final source = await freshRepo();
    await source.addNote(note('a', 'Alpha', DateTime(2026, 1, 1)));
    await source.addNote(note('b', 'Beta', DateTime(2026, 1, 2)));
    await source.addGroup(NoteGroupEntity(
        id: 'g', name: 'work', noteIds: const ['a'], lastModified: DateTime(2026)));

    final bytes = await BackupService(source).export();

    final target = await freshRepo();
    final result = await BackupService(target).restore(bytes);

    expect(result.added, 2);
    final notes = (await target.getNotes()).getOrElse(() => const []);
    expect(notes.map((x) => x.title).toSet(), {'Alpha', 'Beta'});
    final code = notes.firstWhere((x) => x.id == 'a').blocks.single as CodeBlockEntity;
    expect(code.language, Language.rust);
    final groups = (await target.getGroups()).getOrElse(() => const []);
    expect(groups.single.noteIds, ['a']);
  });

  test('restore keeps the newer copy and never deletes', () async {
    final backupSide = await freshRepo();
    await backupSide.addNote(note('a', 'Old title', DateTime(2026, 1, 1)));
    await backupSide.addNote(note('b', 'Newer in backup', DateTime(2026, 5, 1)));
    final bytes = await BackupService(backupSide).export();

    final device = await freshRepo();
    await device.addNote(note('a', 'Edited here later', DateTime(2026, 3, 1)));
    await device.addNote(note('b', 'Stale here', DateTime(2026, 2, 1)));
    await device.addNote(note('c', 'Only here', DateTime(2026, 1, 1)));

    final result = await BackupService(device).restore(bytes);
    final byId = {
      for (final x in (await device.getNotes()).getOrElse(() => const [])) x.id: x
    };

    expect(byId['a']!.title, 'Edited here later'); // device copy was newer
    expect(byId['b']!.title, 'Newer in backup'); // backup copy was newer
    expect(byId['c']!.title, 'Only here'); // untouched
    expect(result.kept, 1);
    expect(result.updated, 1);
  });

  test('rejects files that are not backups', () async {
    final repo = await freshRepo();
    expect(
      () => BackupService(repo).restore(Uint8List.fromList('hello'.codeUnits)),
      throwsA(isA<BackupException>()),
    );
  });
}
