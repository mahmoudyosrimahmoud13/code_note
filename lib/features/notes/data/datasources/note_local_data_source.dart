import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note_model.dart';

abstract class NoteLocalDataSource {
  Future<List<NoteModel>> getLastNotes();
  Future<void> cacheNotes(List<NoteModel> notesToCache);
}

const CACHED_NOTES = 'CACHED_NOTES';

class NoteLocalDataSourceImpl implements NoteLocalDataSource {
  final SharedPreferences sharedPreferences;

  NoteLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<List<NoteModel>> getLastNotes() {
    final jsonString = sharedPreferences.getString(CACHED_NOTES);
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
      CACHED_NOTES,
      json.encode(notesToCache.map((i) => i.toJson()).toList()),
    );
  }
}
