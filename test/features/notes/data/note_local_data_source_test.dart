import 'dart:convert';
import 'dart:io';

import 'package:code_note/features/notes/data/datasources/note_local_data_source.dart';
import 'package:code_note/features/notes/data/models/note_group_model.dart';
import 'package:code_note/features/notes/data/models/note_model.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

NoteModel _note(String id, {String title = 'note', bool trashed = false, DateTime? trashedAt}) {
  return NoteModel(
    id: id,
    title: title,
    tags: const ['test'],
    lastModified: DateTime(2026, 1, 1),
    blocks: [NoteBlockEntity(id: '$id-b', text: 'hello $id')],
    isTrashed: trashed,
    trashTimestamp: trashedAt,
  );
}

void main() {
  late Directory dir;
  late Box box;
  var counter = 0;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('codenote_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    box = await Hive.openBox('notes_${counter++}');
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  tearDownAll(() {
    dir.deleteSync(recursive: true);
  });

  test('moves notes saved in the old single-text format to one entry each', () async {
    await box.put(legacyNotesKey,
        json.encode([_note('a').toJson(), _note('b').toJson()]));
    await box.put(legacyGroupsKey, json.encode([
      NoteGroupModel(id: 'g', name: 'g', noteIds: const ['a'], lastModified: DateTime(2026)).toJson(),
    ]));

    final source = NoteLocalDataSourceImpl(box: box);
    final notes = await source.getLastNotes();
    final groups = await source.getLastGroups();

    expect(notes.map((n) => n.id).toSet(), {'a', 'b'});
    expect(groups.single.noteIds, ['a']);
    expect(box.get(legacyNotesKey), isNull);
    expect(box.containsKey('${notePrefix}a'), isTrue);
  });

  test('saving one note writes only that note', () async {
    final source = NoteLocalDataSourceImpl(box: box);
    await source.saveNote(_note('a'));
    await source.saveNote(_note('b'));
    await source.saveNote(_note('a', title: 'changed'));

    expect(box.keys.where((k) => '$k'.startsWith(notePrefix)).length, 2);
    expect((await source.getNote('a'))!.title, 'changed');
  });

  test('deleting removes the note for good', () async {
    final source = NoteLocalDataSourceImpl(box: box);
    await source.saveNote(_note('a'));
    await source.deleteNote('a');

    expect(await source.getNote('a'), isNull);
    expect(box.containsKey('${notePrefix}a'), isFalse);
  });

  test('watchNotes emits the current list, then every change', () async {
    final source = NoteLocalDataSourceImpl(box: box);
    await source.saveNote(_note('a'));

    final emitted = <int>[];
    final sub = source.watchNotes().listen((n) => emitted.add(n.length));
    await Future<void>.delayed(Duration.zero);
    await source.saveNote(_note('b'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emitted.first, 1);
    expect(emitted.last, 2);
  });

  test('purges only notes trashed longer than the limit', () async {
    final source = NoteLocalDataSourceImpl(box: box);
    final now = DateTime.now();
    await source.saveNote(_note('old', trashed: true, trashedAt: now.subtract(const Duration(days: 40))));
    await source.saveNote(_note('recent', trashed: true, trashedAt: now.subtract(const Duration(days: 2))));
    await source.saveNote(_note('kept'));

    final removed = await source.purgeOldTrash(const Duration(days: 30));

    expect(removed.map((n) => n.id), ['old']);
    expect((await source.getLastNotes()).map((n) => n.id).toSet(), {'recent', 'kept'});
  });
}
