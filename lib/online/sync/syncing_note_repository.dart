import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../features/notes/domain/entities/note.dart';
import '../../features/notes/domain/entities/note_group.dart';
import '../../features/notes/domain/repositories/note_repository.dart';
import 'notes_sync.dart';

/// The normal note storage, plus a note to [NotesSync] after every change so
/// it reaches your other devices.
class SyncingNoteRepository implements NoteRepository {
  SyncingNoteRepository(this._inner);
  final NoteRepository _inner;

  NotesSync get _sync => NotesSync.instance;

  Future<Either<Failure, void>> _after(Future<Either<Failure, void>> work, String kind, String id,
      {bool deleted = false}) async {
    final r = await work;
    if (r.isRight()) await _sync.changed(kind, id, deleted: deleted);
    return r;
  }

  @override
  Future<Either<Failure, List<NoteEntity>>> getNotes() => _inner.getNotes();

  @override
  Future<Either<Failure, void>> addNote(NoteEntity note) => _after(_inner.addNote(note), 'note', note.id);

  @override
  Future<Either<Failure, void>> updateNote(NoteEntity note) => _after(_inner.updateNote(note), 'note', note.id);

  @override
  Future<Either<Failure, void>> deleteNote(String id) async {
    // Deleting a note also takes it out of its folders.
    final groupsBefore = await _groupIdsContaining(id);
    final r = await _after(_inner.deleteNote(id), 'note', id, deleted: true);
    for (final g in groupsBefore) {
      await _sync.changed('group', g);
    }
    return r;
  }

  Future<List<String>> _groupIdsContaining(String noteId) async {
    final groups = (await _inner.getGroups()).getOrElse(() => const []);
    return [for (final g in groups) if (g.noteIds.contains(noteId)) g.id];
  }

  @override
  Future<Either<Failure, int>> purgeOldTrash() async {
    final before = (await _inner.getNotes()).getOrElse(() => const []).map((n) => n.id).toSet();
    final r = await _inner.purgeOldTrash();
    if (r.isRight() && r.getOrElse(() => 0) > 0) {
      final after = (await _inner.getNotes()).getOrElse(() => const []).map((n) => n.id).toSet();
      for (final id in before.difference(after)) {
        await _sync.changed('note', id, deleted: true);
      }
    }
    return r;
  }

  @override
  Future<Either<Failure, NoteEntity?>> getNoteById(String id) => _inner.getNoteById(id);

  @override
  Future<Either<Failure, List<NoteGroupEntity>>> getGroups() => _inner.getGroups();

  @override
  Future<Either<Failure, void>> addGroup(NoteGroupEntity group) => _after(_inner.addGroup(group), 'group', group.id);

  @override
  Future<Either<Failure, void>> updateGroup(NoteGroupEntity group) => _after(_inner.updateGroup(group), 'group', group.id);

  @override
  Future<Either<Failure, void>> deleteGroup(String id) => _after(_inner.deleteGroup(id), 'group', id, deleted: true);

  @override
  Stream<List<NoteEntity>> watchNotes() => _inner.watchNotes();

  @override
  Stream<List<NoteGroupEntity>> watchGroups() => _inner.watchGroups();

  @override
  Future<Either<Failure, void>> sync() async {
    await _sync.syncNow();
    return const Right(null);
  }
}
