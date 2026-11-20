import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../python_kernel.dart';
import '../runtimes.dart';
import 'pyodide_runtime.dart';

/// A note's Python kernel on a phone: a Pyodide worker in the web view.
/// It runs CodeNote's same codenote_kernel.py as computers, so blocks,
/// Run note, Run folder and workspaces behave the same.
class PyodideKernel implements NotebookKernel {
  PyodideKernel._(this.noteId, this.workspace);

  final String noteId;
  final Directory workspace;
  final _queue = <KernelCell>[];
  final _codes = <String, String>{};
  final _files = <String, String>{};
  KernelCell? _current;
  bool _dead = false;
  final _ready = Completer<void>();
  String? _error;

  @override
  String version = '';

  @override
  bool get alive => !_dead;

  String get _id => 'note-$noteId';

  static Future<PyodideKernel> start(String noteId, Directory workspace) async {
    final rt = PyodideRuntime.instance;
    if (!await rt.isInstalled()) {
      throw RuntimeException("Python for phones isn't downloaded yet. Open Settings > Runtimes and sandbox.");
    }
    final k = PyodideKernel._(noteId, workspace);
    rt.listen(k._id, k._onMessage);
    await rt.send({'op': 'start', 'kernel': k._id});
    await k._ready.future.timeout(const Duration(minutes: 2), onTimeout: () {
      k._error ??= 'Python took too long to start.';
    });
    if (k._dead || k._error != null) {
      rt.forget(k._id);
      throw RuntimeException("Python couldn't start: ${k._error ?? 'unknown problem'}");
    }
    return k;
  }

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'ready':
        version = '${m['version'] ?? ''}';
        if (!_ready.isCompleted) _ready.complete();
      case 'died':
        _error = '${m['error'] ?? 'stopped'}';
        _onExit();
      case 'file':
        _saveFile('${m['path']}', '${m['data']}');
      case 'line':
        _onLine('${m['text'] ?? ''}');
    }
  }

  /// A plot or table made in the worker: saved into the note's sandbox so
  /// the output (and "Save output") work like on a computer.
  void _saveFile(String path, String data) {
    try {
      final dir = Directory(p.join(workspace.path, '.codenote', 'out'))..createSync(recursive: true);
      final local = p.join(dir.path, p.basename(path));
      File(local).writeAsBytesSync(base64Decode(data));
      _files[path] = local;
    } catch (_) {}
  }

  void _onLine(String line) {
    var text = line;
    final plain = RunningProcess.plain(text);
    if (plain.startsWith(outputMark)) {
      final msg = plain.substring(outputMark.length);
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
      // Point rich output at the copy in the sandbox.
      for (final e in _files.entries) {
        if (text.contains(e.key)) text = text.replaceFirst(e.key, e.value);
      }
    }
    _current?.onLine(text);
  }

  void _onExit() {
    _dead = true;
    if (!_ready.isCompleted) _ready.complete();
    PyodideRuntime.instance.forget(_id);
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
    unawaited(PyodideRuntime.instance
        .send({'op': 'run', 'kernel': _id, 'cell': cell.id, 'code': _codes.remove(cell.id) ?? ''})
        .catchError((Object e) {
      _error = '$e';
      _onExit();
    }));
  }

  @override
  Future<String> execute(String id, String code, void Function(String line) onLine) async {
    if (_dead) return 'died';
    final cell = KernelCell(id, '', onLine);
    _codes[id] = code;
    _queue.add(cell);
    _next();
    return cell.done.future;
  }

  @override
  void send(String text) {
    unawaited(PyodideRuntime.instance
        .send({'op': 'input', 'kernel': _id, 'text': text.endsWith('\n') ? text.substring(0, text.length - 1) : text})
        .catchError((_) {}));
  }

  @override
  Future<void> interrupt() async {
    final cell = _current;
    if (cell == null) return;
    await PyodideRuntime.instance.send({'op': 'interrupt', 'kernel': _id});
    await cell.done.future.timeout(const Duration(seconds: 3), onTimeout: () {
      shutdown();
      return 'died';
    });
  }

  @override
  void shutdown() {
    if (_dead) return;
    unawaited(PyodideRuntime.instance.send({'op': 'stop', 'kernel': _id}).catchError((_) {}));
    _onExit();
  }
}
