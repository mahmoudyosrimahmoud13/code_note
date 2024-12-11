import 'package:bloc/bloc.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/models/note_model.dart';

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

part 'note_state.dart';

final List<Note> notes = [];

class NoteCubit extends Cubit<NoteState> {
  NoteCubit() : super(NoteInitial());
  void initializeNote({required List<Note> notes}) {
    emit(NoteLoading());
    emit(NoteSuccess());
  }
}
