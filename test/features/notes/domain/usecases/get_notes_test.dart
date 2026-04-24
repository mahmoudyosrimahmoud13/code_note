import 'package:dartz/dartz.dart';
import 'package:code_note/core/usecases/usecase.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/notes/domain/repositories/note_repository.dart';
import 'package:code_note/features/notes/domain/usecases/get_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNoteRepository extends Mock implements NoteRepository {}

void main() {
  late GetNotes usecase;
  late MockNoteRepository mockNoteRepository;

  setUp(() {
    mockNoteRepository = MockNoteRepository();
    usecase = GetNotes(mockNoteRepository);
  });

  final tNotes = [
    NoteEntity(
      id: '1',
      title: 'Test Note',
      tags: const ['test'],
      lastModified: DateTime.now(),
      blocks: const [],
    )
  ];

  test(
    'should get notes from the repository',
    () async {
      // arrange
      when(() => mockNoteRepository.getNotes())
          .thenAnswer((_) async => Right(tNotes));
      // act
      final result = await usecase(NoParams());
      // assert
      expect(result, Right(tNotes));
      verify(() => mockNoteRepository.getNotes());
      verifyNoMoreInteractions(mockNoteRepository);
    },
  );
}
