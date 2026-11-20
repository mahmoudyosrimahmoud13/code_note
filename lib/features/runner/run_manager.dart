import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import 'code_runner.dart';
import 'runtimes.dart';

/// One run of a code block. It keeps going when the note is closed, so a
/// server in one note can serve a page in another.
class RunSession extends ChangeNotifier {
  RunSession({required this.blockId, required this.title, required this.spaceKey});

  final String blockId;
  final String title;
  final String spaceKey;
  final DateTime startedAt = DateTime.now();

  /// Output lines; error lines start with [RunningProcess.errorMark].
  final List<String> lines = [];
  RunningProcess? _process;
  int? exitCode;
  String? error;

  bool get running => _process != null && exitCode == null && error == null;

  static const _maxLines = 3000;

  void _add(String line) {
    lines.add(line);
    if (lines.length > _maxLines) lines.removeRange(0, lines.length - _maxLines);
    notifyListeners();
  }

  void stop() => _process?.stop();

  void _changed() => notifyListeners();

  void send(String text) => _process?.write(text);

  /// Output as plain text (for "Save output to note").
  String get text => lines
      .map((l) => l.startsWith(RunningProcess.errorMark) ? l.substring(1) : l)
      .join('\n');
}

/// All runs in the app. Shown under code blocks, in Settings and in the
/// Terminal, with "Stop all".
class RunManager extends ChangeNotifier {
  RunManager._();
  static final RunManager instance = RunManager._();

  final Map<String, RunSession> _sessions = {};

  RunSession? sessionFor(String blockId) => _sessions[blockId];

  List<RunSession> get running => _sessions.values.where((s) => s.running).toList();

  /// Runs a code block. A block runs once at a time: running it again
  /// stops the old run first.
  Future<RunSession> run({
    required String blockId,
    required String title,
    required String spaceKey,
    required Language language,
    required String code,
  }) async {
    final old = _sessions[blockId];
    if (old != null && old.running) {
      old.stop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final session = RunSession(blockId: blockId, title: title, spaceKey: spaceKey);
    _sessions[blockId] = session;
    notifyListeners();
    try {
      final proc = await CodeRunner.run(spaceKey: spaceKey, language: language, code: code);
      session._process = proc;
      session._changed();
      proc.lines.listen(session._add);
      unawaited(proc.exitCode.then((code) {
        session.exitCode = code;
        session._changed();
        notifyListeners();
      }));
    } on RuntimeException catch (e) {
      session.error = e.message;
      session._changed();
    } catch (e) {
      session.error = '$e';
      session._changed();
    }
    notifyListeners();
    return session;
  }

  /// What Run folder starts in [notes], note by note: a note's ★ main
  /// block alone if it has one, otherwise every block not marked skip.
  static List<(NoteEntity, List<CodeBlockEntity>)> runnable(List<NoteEntity> notes) => [
        for (final n in notes)
          if (!n.isTrashed) (n, folderBlocks(n)),
      ].where((e) => e.$2.isNotEmpty).toList();

  static List<CodeBlockEntity> folderBlocks(NoteEntity note) {
    final code = note.blocks
        .whereType<CodeBlockEntity>()
        .where((b) => CodeRunner.canRun(b.language) && (b.text ?? '').trim().isNotEmpty)
        .toList();
    final main = code.where((b) => b.runRole == RunRole.main);
    if (main.isNotEmpty) return [main.first];
    return code.where((b) => b.runRole != RunRole.skip).toList();
  }

  /// Runs a whole folder: notes side by side; inside a note, blocks run in
  /// order and each waits for the one before it, except the last, which may
  /// keep running (a server). Returns the first problem, if any.
  Future<String?> runFolder(List<NoteEntity> notes, String spaceKey) async {
    String? problem;
    Future<void> runNote(NoteEntity note, List<CodeBlockEntity> blocks) async {
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        final s = await run(
          blockId: b.id,
          title: note.title,
          spaceKey: spaceKey,
          language: b.language,
          code: b.text ?? '',
        );
        if (s.error != null) {
          problem ??= s.error;
          return;
        }
        if (i < blocks.length - 1) {
          final code = await s._process!.exitCode;
          if (code != 0) {
            problem ??= '"${note.title}" stopped with an error. Open it to see the output.';
            return;
          }
        }
      }
    }

    await Future.wait([for (final (n, blocks) in runnable(notes)) runNote(n, blocks)]);
    return problem;
  }

  /// True if any block of these notes is running.
  bool folderRunning(List<NoteEntity> notes) =>
      notes.any((n) => anyRunning(n.blocks.map((b) => b.id)));

  void stopFolder(List<NoteEntity> notes) {
    for (final n in notes) {
      for (final b in n.blocks) {
        final s = _sessions[b.id];
        if (s != null && s.running) s.stop();
      }
    }
  }

  void clear(String blockId) {
    final s = _sessions[blockId];
    if (s == null || s.running) return;
    _sessions.remove(blockId);
    notifyListeners();
  }

  /// True if any block of these is running (for the badge on note cards).
  bool anyRunning(Iterable<String> blockIds) =>
      blockIds.any((id) => _sessions[id]?.running ?? false);

  void stopAll() {
    for (final s in running) {
      s.stop();
    }
  }
}
