import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/note_model.dart';
import '../models/note_group_model.dart';

abstract class NoteLocalDataSource {
  Future<List<NoteModel>> getLastNotes();
  Future<void> cacheNotes(List<NoteModel> notesToCache);
  Future<List<NoteGroupModel>> getLastGroups();
  Future<void> cacheGroups(List<NoteGroupModel> groupsToCache);
  Future<void> updateSingleNote(NoteModel note);
  Stream<List<NoteModel>> watchNotes();
  Stream<List<NoteGroupModel>> watchGroups();
}

const cachedNotesKey = 'CACHED_NOTES';
const cachedGroupsKey = 'CACHED_GROUPS';

class NoteLocalDataSourceImpl implements NoteLocalDataSource {
  final Box box;

  NoteLocalDataSourceImpl({required this.box});

  @override
  Future<List<NoteModel>> getLastNotes() async {
    final jsonString = box.get(cachedNotesKey);
    if (jsonString != null) {
      try {
        return (json.decode(jsonString) as List)
            .map((i) => NoteModel.fromJson(i))
            .toList();
      } catch (e) {
        return [];
      }
    } else {
      return [];
    }
  }

  @override
  Future<void> cacheNotes(List<NoteModel> notesToCache) async {
    await box.put(
      cachedNotesKey,
      json.encode(notesToCache.map((i) => i.toJson()).toList()),
    );
  }

  @override
  Future<List<NoteGroupModel>> getLastGroups() async {
    final jsonString = box.get(cachedGroupsKey);
    if (jsonString != null) {
      try {
        return (json.decode(jsonString) as List)
            .map((i) => NoteGroupModel.fromJson(i))
            .toList();
      } catch (e) {
        return [];
      }
    } else {
      return [];
    }
  }

  @override
  Future<void> cacheGroups(List<NoteGroupModel> groupsToCache) async {
    await box.put(
      cachedGroupsKey,
      json.encode(groupsToCache.map((i) => i.toJson()).toList()),
    );
  }

  @override
  Future<void> updateSingleNote(NoteModel note) async {
    final notes = await getLastNotes();
    final index = notes.indexWhere((i) => i.id == note.id);
    if (index != -1) {
      notes[index] = note;
    } else {
      notes.add(note);
    }
    await cacheNotes(notes);
  }

  @override
  Stream<List<NoteModel>> watchNotes() async* {
    // Emit initial value immediately
    yield await getLastNotes();
    
    // Then yield values on every change
    await for (final _ in box.watch(key: cachedNotesKey)) {
      yield await getLastNotes();
    }
  }

  @override
  Stream<List<NoteGroupModel>> watchGroups() async* {
    // Emit initial value immediately
    yield await getLastGroups();
    
    // Then yield values on every change
    await for (final _ in box.watch(key: cachedGroupsKey)) {
      yield await getLastGroups();
    }
  }
}
