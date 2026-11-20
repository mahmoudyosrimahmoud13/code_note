import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import '../notes/domain/entities/run_plan.dart';
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

  /// The blocks a note runs, in order: top to bottom without the skipped
  /// ones, and the ★ primary block moved to the end.
  static List<CodeBlockEntity> folderBlocks(NoteEntity note) {
    final code = note.blocks
        .whereType<CodeBlockEntity>()
        .where((b) => CodeRunner.canRunIn(b.language, note.blocks) && (b.text ?? '').trim().isNotEmpty)
        .where((b) => b.runRole != RunRole.skip)
        .toList();
    final primary = code.where((b) => b.runRole == RunRole.main).toList();
    if (primary.isEmpty) return code;
    return [...code.where((b) => b != primary.first), primary.first];
  }

  /// Note id → what its "Run note" sequence is doing now.
  final Map<String, String> noteStatus = {};

  /// Runs one note's blocks as a sequence. The last block keeps running
  /// unless [waitForLast]. Returns the first problem, if any.
  Future<String?> _runNoteSequence(NoteEntity note, String spaceKey,
      {required bool waitForLast, required String stopKey}) async {
    final blocks = folderBlocks(note);
    for (var j = 0; j < blocks.length; j++) {
      if (_stopping.contains(stopKey)) return 'Stopped.';
      final b = blocks[j];
      final last = j == blocks.length - 1;
      final s = await run(blockId: b.id, title: note.title, spaceKey: spaceKey, language: b.language, code: b.text ?? '');
      if (s.error != null) return s.error;
      final waits = last ? waitForLast : b.runRole != RunRole.background;
      if (waits) {
        final code = await s._process!.exitCode;
        if (_stopping.contains(stopKey)) return 'Stopped.';
        if (code != 0) {
          return '"${note.title.isEmpty ? 'Untitled' : note.title}" stopped with an error, so the run stopped there. Open it to see the output.';
        }
      } else if (!last) {
        // Keeps running: give it a moment to start before the next block.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }
    return null;
  }

  /// ▶ Run note: the note's blocks in order, primary last and left running.
  Future<String?> runNote(NoteEntity note, String spaceKey) async {
    _stopping.remove(note.id);
    noteStatus[note.id] = 'running';
    notifyListeners();
    try {
      return await _runNoteSequence(note, spaceKey, waitForLast: false, stopKey: note.id);
    } finally {
      noteStatus.remove(note.id);
      _stopping.remove(note.id);
      notifyListeners();
    }
  }

  void stopNote(NoteEntity note) {
    if (noteStatus.containsKey(note.id)) _stopping.add(note.id);
    for (final b in note.blocks) {
      final s = _sessions[b.id];
      if (s != null && s.running) s.stop();
    }
  }

  /// Folder id → what its sequence is doing now ("step 2 of 4: Backend").
  final Map<String, String> folderStatus = {};
  final Set<String> _stopping = {};

  /// The notes of [group] that have something to run, in folder order.
  static List<NoteEntity> runnableNotes(NoteGroupEntity group, List<NoteEntity> notes) {
    final byId = {for (final n in notes) n.id: n};
    return [
      for (final id in group.noteIds)
        if (byId[id] != null && !byId[id]!.isTrashed && folderBlocks(byId[id]!).isNotEmpty) byId[id]!,
    ];
  }

  /// Runs a folder as a sequence: notes one after another in the folder's
  /// run order, each finishing before the next starts (unless marked "keep
  /// running"), and the primary note last, left running. Inside a note,
  /// blocks run top to bottom. Returns the first problem, if any.
  Future<String?> runFolder(NoteGroupEntity group, List<NoteEntity> notes, String spaceKey) async {
    final runnable = runnableNotes(group, notes);
    final byId = {for (final n in runnable) n.id: n};
    final steps = (group.runPlan ?? const RunPlan()).steps(runnable.map((n) => n.id).toList());
    _stopping.remove(group.id);
    try {
      for (var i = 0; i < steps.length; i++) {
        if (_stopping.contains(group.id)) return 'Stopped.';
        final step = steps[i];
        final note = byId[step.noteId]!;
        folderStatus[group.id] =
            'step ${i + 1} of ${steps.length}: ${note.title.isEmpty ? 'Untitled' : note.title}${step.primary ? ' (primary)' : ''}';
        notifyListeners();
        final problem = await _runNoteSequence(note, spaceKey,
            waitForLast: step.wait, stopKey: group.id);
        if (problem != null) return problem;
        if (!step.wait && !step.primary) {
          // A note that keeps running: give it a moment to start.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
      }
      return null;
    } finally {
      folderStatus.remove(group.id);
      _stopping.remove(group.id);
      notifyListeners();
    }
  }

  /// True while a folder's sequence is still starting its steps.
  bool sequenceRunning(String folderId) => folderStatus.containsKey(folderId);

  /// True if any block of these notes is running.
  bool folderRunning(List<NoteEntity> notes) =>
      notes.any((n) => anyRunning(n.blocks.map((b) => b.id)));

  void stopFolder(String folderId, List<NoteEntity> notes) {
    if (folderStatus.containsKey(folderId)) _stopping.add(folderId);
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
