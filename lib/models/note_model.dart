import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/block/note_block.dart';

class Note {
  List<Block>? blocks;
  final String id;
  String? title;
  final List<String> tags;
  DateTime lastModified;

  Note(
      {required this.id,
      this.title,
      required this.lastModified,
      required this.tags,
      this.blocks}) {
    blocks ??= [NoteBlock(id: uuid.generate())];
  }
}
