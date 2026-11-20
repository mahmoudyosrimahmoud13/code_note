import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/note_group_model.dart';
import '../models/note_model.dart';

/// Local storage for notes and groups.
///
/// Every note and every group is its own Hive entry (`note:<id>` and
/// `group:<id>`), so saving one note only writes that note. A decoded copy of
/// everything is kept in memory, so reading and watching never decodes the
/// whole store again.
abstract class NoteLocalDataSource {
  Future<List<NoteModel>> getLastNotes();
  Future<NoteModel?> getNote(String id);
  Future<void> saveNote(NoteModel note);
  Future<void> deleteNote(String id);

  Future<List<NoteGroupModel>> getLastGroups();
  Future<void> saveGroup(NoteGroupModel group);
  Future<void> deleteGroup(String id);

  /// Removes notes that have been in the trash longer than [maxAge].
  /// Returns the removed notes so their image files can be cleaned up.
  Future<List<NoteModel>> purgeOldTrash(Duration maxAge);

  Stream<List<NoteModel>> watchNotes();
  Stream<List<NoteGroupModel>> watchGroups();
}

/// Old storage keys: all notes (or groups) as one JSON text.
/// Kept only to migrate existing data the first time the new version runs.
const legacyNotesKey = 'CACHED_NOTES';
const legacyGroupsKey = 'CACHED_GROUPS';

const notePrefix = 'note:';
const groupPrefix = 'group:';

class NoteLocalDataSourceImpl implements NoteLocalDataSource {
  final Box box;

  final Map<String, NoteModel> _notes = {};
  final Map<String, NoteGroupModel> _groups = {};
  final _notesController = StreamController<List<NoteModel>>.broadcast();
  final _groupsController = StreamController<List<NoteGroupModel>>.broadcast();
  StreamSubscription<BoxEvent>? _boxSubscription;

  /// The one loading run. Everyone who asks early waits for this same run,
  /// so nobody sees a half-loaded (empty) list.
  Future<void>? _loading;

  NoteLocalDataSourceImpl({required this.box});

  Future<void> _ensureLoaded() => _loading ??= _load();

  /// Loads everything into memory once, migrating the old format if needed.
  Future<void> _load() async {
    await _migrateLegacy();

    for (final key in box.keys) {
      if (key is! String) continue;
      final raw = box.get(key);
      if (key.startsWith(notePrefix)) {
        final note = _decodeNote(raw);
        if (note != null) _notes[note.id] = note;
      } else if (key.startsWith(groupPrefix)) {
        final group = _decodeGroup(raw);
        if (group != null) _groups[group.id] = group;
      }
    }

    // Keep the memory copy right even if something else changes the box
    // (for example "clear all data" in Settings).
    _boxSubscription = box.watch().listen(_onBoxEvent);
  }

  Future<void> _migrateLegacy() async {
    final oldNotes = box.get(legacyNotesKey);
    if (oldNotes is String) {
      try {
        final list = json.decode(oldNotes) as List;
        for (final item in list) {
          final note = NoteModel.fromJson(Map<String, dynamic>.from(item));
          await box.put('$notePrefix${note.id}', json.encode(note.toJson()));
        }
        await box.delete(legacyNotesKey);
      } catch (_) {
        // Leave the old entry alone if it can't be read, so nothing is lost.
      }
    }

    final oldGroups = box.get(legacyGroupsKey);
    if (oldGroups is String) {
      try {
        final list = json.decode(oldGroups) as List;
        for (final item in list) {
          final group =
              NoteGroupModel.fromJson(Map<String, dynamic>.from(item));
          await box.put('$groupPrefix${group.id}', json.encode(group.toJson()));
        }
        await box.delete(legacyGroupsKey);
      } catch (_) {}
    }
  }

  void _onBoxEvent(BoxEvent event) {
    final key = event.key;
    if (key is! String) return;
    if (key.startsWith(notePrefix)) {
      final id = key.substring(notePrefix.length);
      final note = event.deleted ? null : _decodeNote(event.value);
      final current = _notes[id];
      if (note == null) {
        if (current == null) return;
        _notes.remove(id);
      } else {
        if (current == note) return;
        _notes[id] = note;
      }
      _emitNotes();
    } else if (key.startsWith(groupPrefix)) {
      final id = key.substring(groupPrefix.length);
      final group = event.deleted ? null : _decodeGroup(event.value);
      final current = _groups[id];
      if (group == null) {
        if (current == null) return;
        _groups.remove(id);
      } else {
        if (current == group) return;
        _groups[id] = group;
      }
      _emitGroups();
    }
  }

  NoteModel? _decodeNote(dynamic raw) {
    if (raw is! String) return null;
    try {
      return NoteModel.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  NoteGroupModel? _decodeGroup(dynamic raw) {
    if (raw is! String) return null;
    try {
      return NoteGroupModel.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _emitNotes() {
    if (!_notesController.isClosed) {
      _notesController.add(List.unmodifiable(_notes.values));
    }
  }

  void _emitGroups() {
    if (!_groupsController.isClosed) {
      _groupsController.add(List.unmodifiable(_groups.values));
    }
  }

  // ─── Notes ──────────────────────────────────────────────

  @override
  Future<List<NoteModel>> getLastNotes() async {
    await _ensureLoaded();
    return List.of(_notes.values);
  }

  @override
  Future<NoteModel?> getNote(String id) async {
    await _ensureLoaded();
    return _notes[id];
  }

  @override
  Future<void> saveNote(NoteModel note) async {
    await _ensureLoaded();
    _notes[note.id] = note;
    _emitNotes();
    await box.put('$notePrefix${note.id}', json.encode(note.toJson()));
  }

  @override
  Future<void> deleteNote(String id) async {
    await _ensureLoaded();
    if (_notes.remove(id) != null) _emitNotes();
    await box.delete('$notePrefix$id');
  }

  @override
  Future<List<NoteModel>> purgeOldTrash(Duration maxAge) async {
    await _ensureLoaded();
    final cutoff = DateTime.now().subtract(maxAge);
    final old = _notes.values
        .where((n) =>
            n.isTrashed &&
            (n.trashTimestamp ?? n.lastModified).isBefore(cutoff))
        .toList();
    for (final note in old) {
      _notes.remove(note.id);
    }
    if (old.isNotEmpty) {
      _emitNotes();
      await box.deleteAll(old.map((n) => '$notePrefix${n.id}'));
    }
    return old;
  }

  @override
  Stream<List<NoteModel>> watchNotes() async* {
    await _ensureLoaded();
    yield List.unmodifiable(_notes.values);
    yield* _notesController.stream;
  }

  // ─── Groups ─────────────────────────────────────────────

  @override
  Future<List<NoteGroupModel>> getLastGroups() async {
    await _ensureLoaded();
    return List.of(_groups.values);
  }

  @override
  Future<void> saveGroup(NoteGroupModel group) async {
    await _ensureLoaded();
    _groups[group.id] = group;
    _emitGroups();
    await box.put('$groupPrefix${group.id}', json.encode(group.toJson()));
  }

  @override
  Future<void> deleteGroup(String id) async {
    await _ensureLoaded();
    if (_groups.remove(id) != null) _emitGroups();
    await box.delete('$groupPrefix$id');
  }

  @override
  Stream<List<NoteGroupModel>> watchGroups() async* {
    await _ensureLoaded();
    yield List.unmodifiable(_groups.values);
    yield* _groupsController.stream;
  }

  Future<void> dispose() async {
    await _boxSubscription?.cancel();
    await _notesController.close();
    await _groupsController.close();
  }
}
