import '../entities/block.dart';
import '../entities/note.dart';

/// True when [note] matches a search [query]: its title, a tag, or any
/// text or code inside it. Case doesn't matter, and `#tag` works too.
///
/// Kept here, away from the screens, so it can be tested on its own.
bool noteMatches(NoteEntity note, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (note.title.toLowerCase().contains(q)) return true;
  final tagQuery = q.replaceAll('#', '');
  if (note.tags.any((t) => t.toLowerCase().contains(tagQuery))) return true;
  return note.blocks.any((b) =>
      b is! ImageBlockEntity && (b.text ?? '').toLowerCase().contains(q));
}
