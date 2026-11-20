import 'package:flutter/widgets.dart';

/// Tells blocks which note they belong to and which sandbox it uses
/// (shared by all notes in the same folder).
class NoteScope extends InheritedWidget {
  const NoteScope({
    super.key,
    required this.noteId,
    required this.spaceKey,
    required this.title,
    this.isWebPage = false,
    required super.child,
  });

  final String noteId;
  final String spaceKey;
  final String title;

  /// The note has HTML: its JavaScript belongs to the page, not to Node.
  final bool isWebPage;

  static NoteScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoteScope>();

  @override
  bool updateShouldNotify(NoteScope old) =>
      old.noteId != noteId || old.spaceKey != spaceKey || old.title != title || old.isWebPage != isWebPage;
}
