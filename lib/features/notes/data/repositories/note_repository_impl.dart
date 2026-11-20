import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/block.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_group.dart';
import '../../domain/repositories/note_repository.dart';
import '../datasources/note_local_data_source.dart';
import '../models/note_group_model.dart';
import '../models/note_model.dart';

/// How long a note stays in the trash before it is deleted for good.
const trashRetention = Duration(days: 30);

class NoteRepositoryImpl implements NoteRepository {
  final NoteLocalDataSource localDataSource;

  NoteRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<NoteEntity>>> getNotes() async {
    try {
      return Right(await localDataSource.getLastNotes());
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> addNote(NoteEntity note) => _save(note);

  @override
  Future<Either<Failure, void>> updateNote(NoteEntity note) => _save(note);

  Future<Either<Failure, void>> _save(NoteEntity note) async {
    try {
      final previous = await localDataSource.getNote(note.id);
      final model = NoteModel.fromEntity(note).copyWith(
        isDirty: false,
        // Count every saved change, so the number means something later
        // (for example when syncing is added back).
        version: (previous?.version ?? note.version) + 1,
      );
      await localDataSource.saveNote(model);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  /// Deletes a note for good: the note, its place in groups, and the image
  /// files it owned. Moving to the trash is a normal update with
  /// `isTrashed: true`.
  @override
  Future<Either<Failure, void>> deleteNote(String id) async {
    try {
      final note = await localDataSource.getNote(id);
      await localDataSource.deleteNote(id);
      if (note != null) await _deleteImages([note]);
      await _removeFromGroups({id});
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  /// Deletes notes that sat in the trash longer than [trashRetention].
  @override
  Future<Either<Failure, int>> purgeOldTrash() async {
    try {
      final removed = await localDataSource.purgeOldTrash(trashRetention);
      if (removed.isNotEmpty) {
        await _deleteImages(removed);
        await _removeFromGroups(removed.map((n) => n.id).toSet());
      }
      return Right(removed.length);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  Future<void> _removeFromGroups(Set<String> noteIds) async {
    final groups = await localDataSource.getLastGroups();
    for (final group in groups) {
      if (group.noteIds.any(noteIds.contains)) {
        await localDataSource.saveGroup(NoteGroupModel.fromEntity(
          group.copyWith(
            noteIds: group.noteIds.where((i) => !noteIds.contains(i)).toList(),
          ),
        ));
      }
    }
  }

  /// Removes image files that CodeNote copied into its own folder.
  /// Files outside that folder are never touched.
  Future<void> _deleteImages(List<NoteEntity> notes) async {
    if (kIsWeb) return;
    final stillUsed = (await localDataSource.getLastNotes())
        .expand((n) => n.blocks)
        .whereType<ImageBlockEntity>()
        .map((b) => b.imagePath)
        .toSet();
    for (final note in notes) {
      for (final block in note.blocks.whereType<ImageBlockEntity>()) {
        final path = block.imagePath;
        if (path == null ||
            stillUsed.contains(path) ||
            !path.contains('persistent_images')) {
          continue;
        }
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {
          // A leftover file is harmless; never fail a delete because of it.
        }
      }
    }
  }

  @override
  Future<Either<Failure, NoteEntity?>> getNoteById(String id) async {
    try {
      return Right(await localDataSource.getNote(id));
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  // ─── Groups ─────────────────────────────────────────────

  @override
  Future<Either<Failure, List<NoteGroupEntity>>> getGroups() async {
    try {
      return Right(await localDataSource.getLastGroups());
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> addGroup(NoteGroupEntity group) =>
      updateGroup(group);

  @override
  Future<Either<Failure, void>> updateGroup(NoteGroupEntity group) async {
    try {
      await localDataSource.saveGroup(NoteGroupModel.fromEntity(
        group.copyWith(lastModified: DateTime.now()),
      ));
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> deleteGroup(String id) async {
    try {
      await localDataSource.deleteGroup(id);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> sync() async {
    // Community Edition is local-only: there is nothing to sync.
    return const Right(null);
  }

  @override
  Stream<List<NoteEntity>> watchNotes() => localDataSource.watchNotes();

  @override
  Stream<List<NoteGroupEntity>> watchGroups() => localDataSource.watchGroups();
}
