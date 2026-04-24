import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/note.dart';

abstract class NoteRepository {
  Future<Either<Failure, List<NoteEntity>>> getNotes();
  Future<Either<Failure, void>> addNote(NoteEntity note);
  Future<Either<Failure, void>> updateNote(NoteEntity note);
  Future<Either<Failure, void>> deleteNote(String id);
}
