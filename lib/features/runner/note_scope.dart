import 'package:flutter/widgets.dart';

import 'notebook_focus.dart';

/// Tells blocks which note they belong to and which sandbox it uses
/// (shared by all notes in the same folder).
class NoteScope extends InheritedWidget {
  const NoteScope({
    super.key,
    required this.noteId,
    required this.spaceKey,
    required this.title,
    this.isWebPage = false,
    this.notebook,
    required super.child,
  });

  final String noteId;
  final String spaceKey;
  final String title;

  /// The note has HTML: its JavaScript belongs to the page, not to Node.
  final bool isWebPage;

  /// Jupyter-style keyboard actions across the note's blocks.
  final NotebookActions? notebook;

  static NoteScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteScope>();

  @override
  bool updateShouldNotify(NoteScope old) =>
      old.noteId != noteId || old.spaceKey != spaceKey || old.title != title || old.isWebPage != isWebPage;
}
