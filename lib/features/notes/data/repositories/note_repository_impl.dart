import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/note.dart';
import '../../domain/repositories/note_repository.dart';
import '../datasources/note_local_data_source.dart';
import '../models/note_model.dart';

class NoteRepositoryImpl implements NoteRepository {
  final NoteLocalDataSource localDataSource;

  NoteRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<NoteEntity>>> getNotes() async {
    try {
      final localNotes = await localDataSource.getLastNotes();
      return Right(localNotes);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> addNote(NoteEntity note) async {
    try {
      final notes = await localDataSource.getLastNotes();
      final model = NoteModel(
        id: note.id,
        title: note.title,
        tags: note.tags,
        lastModified: note.lastModified,
        blocks: note.blocks,
        isPinned: note.isPinned,
        isArchived: note.isArchived,
        isDeleted: note.isDeleted,
      );
      notes.add(model);
      await localDataSource.cacheNotes(notes);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> updateNote(NoteEntity note) async {
    try {
      final notes = await localDataSource.getLastNotes();
      final index = notes.indexWhere((i) => i.id == note.id);
      final model = NoteModel(
        id: note.id,
        title: note.title,
        tags: note.tags,
        lastModified: note.lastModified,
        blocks: note.blocks,
        isPinned: note.isPinned,
        isArchived: note.isArchived,
        isDeleted: note.isDeleted,
      );
      
      if (index != -1) {
        notes[index] = model;
      } else {
        notes.add(model);
      }
      
      await localDataSource.cacheNotes(notes);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> deleteNote(String id) async {
    try {
      final notes = await localDataSource.getLastNotes();
      notes.removeWhere((i) => i.id == id);
      await localDataSource.cacheNotes(notes);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }
}
