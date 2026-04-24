import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/note_group.dart';
import '../../domain/repositories/note_repository.dart';
import '../datasources/note_local_data_source.dart';
import '../models/note_model.dart';
import '../models/note_group_model.dart';

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
      final model = NoteModel.fromEntity(note);
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
      final model = NoteModel.fromEntity(note);
      
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

  @override
  Future<Either<Failure, List<NoteGroupEntity>>> getGroups() async {
    try {
      final localGroups = await localDataSource.getLastGroups();
      return Right(localGroups);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> addGroup(NoteGroupEntity group) async {
    try {
      final groups = await localDataSource.getLastGroups();
      final model = NoteGroupModel.fromEntity(group);
      groups.add(model);
      await localDataSource.cacheGroups(groups);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> updateGroup(NoteGroupEntity group) async {
    try {
      final groups = await localDataSource.getLastGroups();
      final index = groups.indexWhere((i) => i.id == group.id);
      final model = NoteGroupModel.fromEntity(group);
      
      if (index != -1) {
        groups[index] = model;
      } else {
        groups.add(model);
      }
      
      await localDataSource.cacheGroups(groups);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> deleteGroup(String id) async {
    try {
      final groups = await localDataSource.getLastGroups();
      groups.removeWhere((NoteGroupModel i) => i.id == id);
      await localDataSource.cacheGroups(groups);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }
}
