import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import '../notes/domain/entities/run_plan.dart';
import 'code_runner.dart';
import 'python_kernel.dart';
import 'runtimes.dart';
import 'sandbox.dart';

/// One piece of rich output: an image, a table, markdown or an HTML page
/// (made by CodeNote's Python helpers, like Jupyter's display).
class RichOutput {
  const RichOutput(this.kind, this.path, [this.note = '']);
  final String kind; // image | table | markdown | html
  final String path;
  final String note;

  /// Reads a line like "\u001ecodenote:image:/path|note".
  static RichOutput? parse(String line) {
    final text = RunningProcess.plain(line);
    if (!text.startsWith(outputMark)) return null;
    final rest = text.substring(outputMark.length);
    final colon = rest.indexOf(':');
    if (colon < 0) return null;
    final kind = rest.substring(0, colon);
    if (!const {'image', 'table', 'markdown', 'html'}.contains(kind)) return null;
    final value = rest.substring(colon + 1);
    final bar = value.lastIndexOf('|');
    return bar < 0 ? RichOutput(kind, value) : RichOutput(kind, value.substring(0, bar), value.substring(bar + 1));
  }
}

/// One run of a code block. It keeps going when the note is closed, so a
/// server in one note can serve a page in another.
class RunSession extends ChangeNotifier {
  RunSession({required this.blockId, required this.title, required this.spaceKey, this.inKernel = false, this.noteId});

  final String blockId;
  final String title;
  final String spaceKey;
  final DateTime startedAt = DateTime.now();

  /// Ran in the note's shared Python kernel (variables stay between blocks).
  final bool inKernel;
  final String? noteId;

  /// Jupyter's execution count: In [3].
  int? count;

  /// Output lines; error lines start with [RunningProcess.errorMark], rich
  /// output lines with [outputMark] (see [RichOutput]).
  final List<String> lines = [];
  bool _started = false;
  void Function()? _stop;
  void Function(String text)? _send;
  final _done = Completer<int>();
  int? exitCode;
  String? error;

  /// Finishes with the exit code (0 when all went well).
  Future<int> get done => _done.future;

  bool get running => _started && exitCode == null && error == null;

  static const _maxLines = 3000;

  void _add(String line) {
    final text = RunningProcess.plain(line);
    if (text.startsWith('${outputMark}count:')) {
      count = int.tryParse(text.substring(outputMark.length + 6));
      notifyListeners();
      return;
    }
    // A progress bar redrawing itself replaces its previous line.
    if (lines.isNotEmpty && lines.last.startsWith(RunningProcess.replaceMark)) lines.removeLast();
    lines.add(line);
    if (lines.length > _maxLines) lines.removeRange(0, lines.length - _maxLines);
    notifyListeners();
  }

  void _finish(int code) {
    if (exitCode != null) return;
    exitCode = code;
    if (!_done.isCompleted) _done.complete(code);
    notifyListeners();
  }

  void _fail(String message) {
    error = message;
    if (!_done.isCompleted) _done.complete(1);
    notifyListeners();
  }

  void stop() => _stop?.call();

  void _changed() => notifyListeners();

  void send(String text) => _send?.call(text);

  /// Rich outputs (plots, tables…) in order.
  List<RichOutput> get rich => lines.map(RichOutput.parse).whereType<RichOutput>().toList();

  /// Output as plain text, without rich output lines (for "Save output").
  String get text => lines
      .where((l) => RichOutput.parse(l) == null)
      .map(RunningProcess.plain)
      .join('\n');
}

/// All runs in the app. Shown under code blocks, in Settings and in the
/// Terminal, with "Stop all".
class RunManager extends ChangeNotifier {
  RunManager._();
  static final RunManager instance = RunManager._();

  final Map<String, RunSession> _sessions = {};

  /// Note id → its Python kernel (blocks of one note share variables).
  final Map<String, PythonKernel> _kernels = {};

  RunSession? sessionFor(String blockId) => _sessions[blockId];

  List<RunSession> get running => _sessions.values.where((s) => s.running).toList();

  bool hasKernel(String noteId) => _kernels[noteId]?.alive ?? false;

  /// Restart kernel: forgets the note's variables, like Jupyter's restart.
  void restartKernel(String noteId) {
    _kernels.remove(noteId)?.shutdown();
    notifyListeners();
  }

  /// Runs a code block. A block runs once at a time: running it again
  /// stops the old run first.
  ///
  /// Python blocks of a note share one kernel, like Jupyter cells, unless
  /// they're ★ primary or "keep running" (servers): those get their own
  /// process so they never block the other blocks.
  Future<RunSession> run({
    required String blockId,
    required String title,
    required String spaceKey,
    required Language language,
    required String code,
    String? noteId,
    RunRole role = RunRole.normal,
  }) async {
    final old = _sessions[blockId];
    if (old != null && old.running) {
      old.stop();
      await old.done.timeout(const Duration(seconds: 4), onTimeout: () => -1);
    }
    final kernel = language == Language.python &&
        noteId != null &&
        role != RunRole.main &&
        role != RunRole.background;
    final session = RunSession(blockId: blockId, title: title, spaceKey: spaceKey, inKernel: kernel, noteId: noteId);
    _sessions[blockId] = session;
    notifyListeners();
    try {
      if (kernel) {
        await _runInKernel(session, noteId, spaceKey, code);
      } else {
        final proc = await CodeRunner.run(spaceKey: spaceKey, language: language, code: code);
        session._started = true;
        session._stop = proc.stop;
        session._send = proc.write;
        session._changed();
        proc.lines.listen(session._add);
        unawaited(proc.exitCode.then((code) {
          session._finish(code);
          notifyListeners();
        }));
      }
    } on RuntimeException catch (e) {
      session._fail(e.message);
    } catch (e) {
      session._fail('$e');
    }
    notifyListeners();
    return session;
  }

  Future<void> _runInKernel(RunSession session, String noteId, String spaceKey, String code) async {
    final allowed = await Sandbox.instance.canRun();
    if (allowed != true) {
      throw RuntimeException(allowed == null
          ? 'Running code is off on this computer until you allow it in Settings > Runtimes and sandbox.'
          : "Code can't run on this device.");
    }
    var kernel = _kernels[noteId];
    if (kernel == null || !kernel.alive) {
      kernel = await PythonKernel.start(noteId, await Sandbox.instance.space(spaceKey));
      _kernels[noteId] = kernel;
    }
    final k = kernel;
    session._started = true;
    session._stop = () => k.interrupt();
    session._send = k.send;
    session._changed();
    unawaited(k.execute(session.blockId, code, session._add).then((status) {
      if (status == 'died') {
        session._add('${RunningProcess.errorMark}The Python kernel stopped. Its variables are gone; run the blocks again.');
        _kernels.remove(noteId);
      }
      session._finish(status == 'ok' ? 0 : status == 'interrupted' ? 130 : 1);
      notifyListeners();
    }));
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
