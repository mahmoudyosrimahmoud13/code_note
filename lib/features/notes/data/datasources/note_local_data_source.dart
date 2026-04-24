import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note_model.dart';
import '../models/note_group_model.dart';

abstract class NoteLocalDataSource {
  Future<List<NoteModel>> getLastNotes();
  Future<void> cacheNotes(List<NoteModel> notesToCache);
  Future<List<NoteGroupModel>> getLastGroups();
  Future<void> cacheGroups(List<NoteGroupModel> groupsToCache);
}

const cachedNotes = 'CACHED_NOTES';
const cachedGroups = 'CACHED_GROUPS';

class NoteLocalDataSourceImpl implements NoteLocalDataSource {
  final SharedPreferences sharedPreferences;

  NoteLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<List<NoteModel>> getLastNotes() {
    final jsonString = sharedPreferences.getString(cachedNotes);
    if (jsonString != null) {
      return Future.value((json.decode(jsonString) as List)
          .map((i) => NoteModel.fromJson(i))
          .toList());
    } else {
      return Future.value([]);
    }
  }

  @override
  Future<void> cacheNotes(List<NoteModel> notesToCache) {
    return sharedPreferences.setString(
      cachedNotes,
      json.encode(notesToCache.map((i) => i.toJson()).toList()),
    );
  }

  @override
  Future<List<NoteGroupModel>> getLastGroups() {
    final jsonString = sharedPreferences.getString(cachedGroups);
    if (jsonString != null) {
      return Future.value((json.decode(jsonString) as List)
          .map((i) => NoteGroupModel.fromJson(i))
          .toList());
    } else {
      return Future.value([]);
    }
  }

  @override
  Future<void> cacheGroups(List<NoteGroupModel> groupsToCache) {
    return sharedPreferences.setString(
      cachedGroups,
      json.encode(groupsToCache.map((i) => i.toJson()).toList()),
    );
  }
}
