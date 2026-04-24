import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/note.dart';
import '../repositories/note_repository.dart';

class GetNotes implements UseCase<List<NoteEntity>, NoParams> {
  final NoteRepository repository;

  GetNotes(this.repository);

  @override
  Future<Either<Failure, List<NoteEntity>>> call(NoParams params) async {
    return await repository.getNotes();
  }
}
