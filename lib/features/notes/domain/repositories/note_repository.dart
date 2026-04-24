import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/note.dart';
import '../entities/note_group.dart';

abstract class NoteRepository {
  Future<Either<Failure, List<NoteEntity>>> getNotes();
  Future<Either<Failure, void>> addNote(NoteEntity note);
  Future<Either<Failure, void>> updateNote(NoteEntity note);
  Future<Either<Failure, void>> deleteNote(String id);

  Future<Either<Failure, List<NoteGroupEntity>>> getGroups();
  Future<Either<Failure, void>> addGroup(NoteGroupEntity group);
  Future<Either<Failure, void>> updateGroup(NoteGroupEntity group);
  Future<Either<Failure, void>> deleteGroup(String id);
}
