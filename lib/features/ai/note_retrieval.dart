import '../../core/util/code_languages.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/note.dart';

/// Picks the notes that best match a question, so only those are sent to
/// the AI. Simple word scoring: title and tag hits count more than body hits.
class NoteRetrieval {
  NoteRetrieval._();

  static const _stopWords = {
    'a', 'an', 'the', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'is', 'are',
    'was', 'were', 'be', 'it', 'this', 'that', 'what', 'how', 'why', 'when',
    'where', 'which', 'who', 'do', 'does', 'did', 'my', 'me', 'i', 'we', 'you',
    'with', 'about', 'can', 'should', 'from', 'by', 'at', 'as', 'have', 'has',
  };

  /// Lowercase words of 2+ characters, minus common filler words.
  static List<String> words(String text) => RegExp(r'[a-zA-Z0-9_#+.\-]{2,}')
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!.replaceAll(RegExp(r'^[.\-]+|[.\-]+$'), ''))
      .where((w) => w.length >= 2 && !_stopWords.contains(w))
      .toList();

  static int score(NoteEntity note, List<String> queryWords) {
    if (queryWords.isEmpty) return 0;
    final title = note.title.toLowerCase();
    final tags = note.tags.map((t) => t.toLowerCase()).toList();
    final body = [
      for (final b in note.blocks)
        if (b is! ImageBlockEntity) (b.text ?? '').toLowerCase(),
      for (final b in note.blocks)
        if (b is CodeBlockEntity) languageInfo(b.language).label.toLowerCase(),
    ].join('\n');
    var total = 0;
    for (final w in queryWords) {
      final bare = w.replaceAll('#', '');
      if (title.contains(bare)) total += 5;
      if (tags.any((t) => t.contains(bare))) total += 4;
      final hits = bare.allMatches(body).length;
      total += hits > 5 ? 5 : hits;
    }
    return total;
  }

  /// The best [limit] notes for [question], highest score first.
  static List<NoteEntity> topNotes(List<NoteEntity> notes, String question,
      {int limit = 6}) {
    final q = words(question);
    final scored = [
      for (final n in notes)
        if (!n.isTrashed) (note: n, score: score(n, q)),
    ]..removeWhere((e) => e.score == 0);
    if (scored.isEmpty) return const [];
    // Keep only notes that match reasonably well compared with the best one.
    final best = scored.map((e) => e.score).reduce((a, b) => a > b ? a : b);
    scored.removeWhere((e) => e.score * 3 < best);
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : b.note.lastModified.compareTo(a.note.lastModified);
    });
    return [for (final e in scored.take(limit)) e.note];
  }

  /// One note as plain text for the prompt, cut to [maxChars].
  static String noteAsText(NoteEntity note, {int maxChars = 3000}) {
    final buf = StringBuffer()
      ..writeln('# ${note.title.trim().isEmpty ? 'Untitled' : note.title.trim()}');
    if (note.tags.isNotEmpty) buf.writeln('tags: ${note.tags.map((t) => '#$t').join(' ')}');
    for (final b in note.blocks) {
      if (b is ImageBlockEntity) {
        buf.writeln('[image]');
      } else if (b is CodeBlockEntity) {
        buf
          ..writeln('```${languageInfo(b.language).short}')
          ..writeln(b.text ?? '')
          ..writeln('```');
      } else {
        buf.writeln(b.text ?? '');
      }
    }
    final s = buf.toString();
    return s.length <= maxChars ? s : '${s.substring(0, maxChars)}\n…(cut)';
  }

  /// The full prompt: numbered notes, then the question.
  static String buildPrompt(String question, List<NoteEntity> notes) {
    final buf = StringBuffer()
      ..writeln('Answer the question using only the notes below. '
          'Mention which notes you used like [1] or [2]. '
          "If the notes don't contain the answer, say so plainly.")
      ..writeln();
    for (var i = 0; i < notes.length; i++) {
      buf
        ..writeln('--- note [${i + 1}] ---')
        ..writeln(noteAsText(notes[i]));
    }
    buf
      ..writeln('--- end of notes ---')
      ..writeln()
      ..writeln('Question: $question');
    return buf.toString();
  }
}
