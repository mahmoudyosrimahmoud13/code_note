import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'python_helpers.dart';
import 'runtimes.dart';

/// Lines starting with this come from CodeNote's Python helpers (rich
/// output and kernel messages), not from the person's code.
const outputMark = '\u001ecodenote:';

/// Writes the Python helpers into a sandbox folder and returns their folder.
Future<Directory> writePythonHelpers(Directory workspace) async {
  final dir = Directory(p.join(workspace.path, '.codenote', 'py'));
  await dir.create(recursive: true);
  for (final e in pythonHelpers.entries) {
    final f = File(p.join(dir.path, e.key));
    if (!await f.exists() || await f.readAsString() != e.value) await f.writeAsString(e.value, flush: true);
  }
  return dir;
}

/// One cell waiting for, or getting, the kernel's attention.
class KernelCell {
  KernelCell(this.id, this.path, this.onLine);
  final String id;
  final String path;
  final void Function(String line) onLine;
  final done = Completer<String>(); // ok | error | interrupted | died
}

/// A Python process per note that keeps variables between blocks, like a
/// Jupyter kernel. Blocks run one at a time, in the order they're sent.
class PythonKernel {
  PythonKernel._(this.noteId, this._process, this.workspace);

  final String noteId;
  final Directory workspace;
  final RunningProcess _process;
  final _queue = <KernelCell>[];
  KernelCell? _current;
  bool _dead = false;
  String version = '';
  final _ready = Completer<void>();

  bool get alive => !_dead;

  static Future<PythonKernel> start(String noteId, Directory workspace) async {
    final py = await Runtimes.instance.pythonForRuns();
    if (py == null) {
      throw RuntimeException("Python isn't set up yet. Open Settings > Runtimes and sandbox.");
    }
    final helpers = await writePythonHelpers(workspace);
    final proc = await Runtimes.instance.start(
      py,
      ['-u', p.join(helpers.path, 'codenote_kernel.py')],
      workDir: workspace,
      extraEnv: {
        'CODENOTE_OUT': p.join(workspace.path, '.codenote', 'out'),
        'CODENOTE_INTERRUPT': _flagPath(workspace, noteId),
      },
    );
    final kernel = PythonKernel._(noteId, proc, workspace);
    proc.lines.listen(kernel._onLine, onDone: kernel._onExit);
    await kernel._ready.future.timeout(const Duration(seconds: 30), onTimeout: () {});
    if (kernel._dead) throw RuntimeException("Python couldn't start. Open Settings > Runtimes and sandbox.");
    return kernel;
  }

  void _onLine(String line) {
    final text = RunningProcess.plain(line);
    if (text.startsWith(outputMark)) {
      final msg = text.substring(outputMark.length);
      if (msg.startsWith('ready:')) {
        version = msg.substring(6);
        if (!_ready.isCompleted) _ready.complete();
        return;
      }
      if (msg.startsWith('done:')) {
        final parts = msg.split(':');
        final cell = _current;
        if (cell != null && parts.length >= 3 && parts[1] == cell.id) {
          _current = null;
          if (!cell.done.isCompleted) cell.done.complete(parts[2]);
          _next();
        }
        return;
      }
    }
    _current?.onLine(line);
  }

  void _onExit() {
    _dead = true;
    if (!_ready.isCompleted) _ready.complete();
    final cells = [if (_current != null) _current!, ..._queue];
    _current = null;
    _queue.clear();
    for (final c in cells) {
      if (!c.done.isCompleted) c.done.complete('died');
    }
  }

  void _next() {
    if (_current != null || _queue.isEmpty || _dead) return;
    final cell = _queue.removeAt(0);
    _current = cell;
    _process.write('${json.encode({'cell': cell.id, 'path': cell.path})}\n');
  }

  /// Runs [code] in the kernel. Output goes to [onLine]; the future says
  /// how it ended: ok, error, interrupted or died.
  Future<String> execute(String id, String code, void Function(String line) onLine) async {
    if (_dead) return 'died';
    final dir = Directory(p.join(workspace.path, '.codenote', 'cells'))..createSync(recursive: true);
    final file = File(p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}.py'));
    await file.writeAsString(code, flush: true);
    final cell = KernelCell(id, file.path, onLine);
    _queue.add(cell);
    _next();
    return cell.done.future;
  }

  /// Answers input() in the running block.
  void send(String text) => _process.write(text);

  static String _flagPath(Directory workspace, String noteId) =>
      p.join(workspace.path, '.codenote', 'interrupt-${noteId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}');

  /// Stops the running block but keeps the variables, like Jupyter's
  /// interrupt. If the block doesn't stop within 3 seconds (stuck in
  /// native code), the kernel restarts.
  Future<void> interrupt() async {
    final cell = _current;
    if (cell == null) return;
    await File(_flagPath(workspace, noteId)).writeAsString('stop');
    await cell.done.future.timeout(const Duration(seconds: 3), onTimeout: () {
      shutdown();
      return 'died';
    });
  }

  void shutdown() {
    _dead = true;
    _process.stop();
  }
}
