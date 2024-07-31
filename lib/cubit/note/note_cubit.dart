import 'package:bloc/bloc.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/models/note_model.dart';
import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/block/code_block.dart';
import 'package:code_note/widgets/custom_button.dart';
import 'package:code_note/widgets/language_drop_down.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

part 'note_state.dart';

class NoteCubit extends Cubit<NoteState> {
  NoteCubit() : super(NoteInitial());
  void addNote() {}
}
