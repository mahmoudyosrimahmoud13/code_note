import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/services/log_service.dart';
import '../../miniapps/mini_app_server.dart';
import '../python_helpers.dart';
import '../runtimes.dart';
import '../sandbox.dart';
import 'pyodide_web.dart';

/// A package in Pyodide's list (built for WebAssembly).
class PyodidePackage {
  const PyodidePackage(this.name, this.version, this.file, this.depends, this.imports);
  final String name;
  final String version;
  final String file;
  final List<String> depends;
  final List<String> imports;
}

/// A downloaded package, for Settings.
class DownloadedPackage {
  const DownloadedPackage(this.name, this.version, this.bytes, {this.fromPypi = false});
  final String name;
  final String version;
  final int bytes;
  final bool fromPypi;
}

/// Python on phones: Pyodide (Python built for WebAssembly) running in an
/// invisible web view, one worker per note. Like the desktop runtimes,
/// everything is downloaded on purpose from Settings, into the sandbox:
/// Python itself (about 12 MB) and each package you choose. Blocks only
/// load what's downloaded, so it all works offline afterwards.
class PyodideRuntime extends ChangeNotifier {
  PyodideRuntime._();
  static final PyodideRuntime instance = PyodideRuntime._();

  static const version = '314.0.8';
  static const _cdn = 'https://cdn.jsdelivr.net/pyodide/v$version/full/';
  static const _platformTag = 'pyemscripten_2026_0_wasm32';
  static const coreFiles = ['pyodide.mjs', 'pyodide.asm.mjs', 'pyodide.asm.wasm', 'python_stdlib.zip', 'pyodide-lock.json'];

  /// Ready-made sets for the Settings page.
  static const dataScience = ['numpy', 'pandas', 'matplotlib', 'seaborn', 'scipy', 'scikit-learn', 'openpyxl'];

  /// Where Python runs as Pyodide: phones. Computers use real Python.
  static bool get usedHere => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<Directory> dir() async {
    final d = Directory(p.join((await Sandbox.instance.runtimesDir()).path, 'pyodide'));
    await d.create(recursive: true);
    return d;
  }

  Future<Directory> _pypiDir() async {
    final d = Directory(p.join((await dir()).path, 'pypi'));
    await d.create(recursive: true);
    return d;
  }

  Future<bool> isInstalled() async {
    final d = await dir();
    for (final f in coreFiles) {
      if (!await File(p.join(d.path, f)).exists()) return false;
    }
    return true;
  }

  // ---------- downloads ----------

  /// Downloads Python itself.
  Future<void> downloadCore({void Function(double progress, String status)? onProgress}) async {
    final d = await dir();
    // Rough sizes, so the bar moves evenly.
    const weights = {'pyodide.mjs': 1, 'pyodide.asm.mjs': 4, 'pyodide.asm.wasm': 50, 'python_stdlib.zip': 25, 'pyodide-lock.json': 2};
    final total = weights.values.reduce((a, b) => a + b);
    var done = 0;
    for (final f in coreFiles) {
      final w = weights[f]!;
      await _get(Uri.parse('$_cdn$f'), File(p.join(d.path, f)),
          (x) => onProgress?.call((done + x * w) / total, 'Downloading Python for phones ($f)…'));
      done += w;
    }
    _lock = null;
    onProgress?.call(1, 'Python is ready.');
    notifyListeners();
  }

  Map<String, PyodidePackage>? _lock;

  Future<Map<String, PyodidePackage>> lock() async {
    if (_lock != null) return _lock!;
    final f = File(p.join((await dir()).path, 'pyodide-lock.json'));
    if (!await f.exists()) return const {};
    final data = json.decode(await f.readAsString()) as Map<String, dynamic>;
    final pkgs = (data['packages'] as Map).cast<String, dynamic>();
    return _lock = {
      for (final e in pkgs.entries)
        e.key: PyodidePackage(
          e.key,
          '${(e.value as Map)['version'] ?? ''}',
          '${(e.value as Map)['file_name'] ?? ''}',
          [for (final d in ((e.value as Map)['depends'] as List? ?? const [])) '$d'],
          [for (final i in ((e.value as Map)['imports'] as List? ?? const [])) '$i'],
        ),
    };
  }

  static String norm(String name) => name.toLowerCase().replaceAll(RegExp(r'[-_.]+'), '-');

  /// The lock name for [name] (any spelling), or null.
  Future<String?> lockName(String name) async {
    final l = await lock();
    if (l.containsKey(name)) return name;
    final n = norm(name);
    for (final k in l.keys) {
      if (norm(k) == n) return k;
    }
    // An import name (sklearn -> scikit-learn, PIL -> pillow).
    for (final pkg in l.values) {
      if (pkg.imports.contains(name)) return pkg.name;
    }
    return null;
  }

  /// [names] plus everything they depend on.
  Future<List<String>> closure(Iterable<String> names) async {
    final l = await lock();
    final seen = <String>{};
    final stack = [...names];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      final pkg = l[n];
      if (pkg == null || !seen.add(n)) continue;
      stack.addAll(pkg.depends);
    }
    return seen.toList()..sort();
  }

  Future<bool> _isDownloaded(PyodidePackage pkg) async =>
      File(p.join((await dir()).path, pkg.file)).exists();

  /// Downloads packages (and what they need). Names can be Pyodide
  /// packages, import names (sklearn) or pure-Python packages from PyPI
  /// (seaborn, openpyxl). Returns the names it couldn't find.
  Future<List<String>> downloadPackages(List<String> names,
      {void Function(double progress, String status)? onProgress}) async {
    if (!await isInstalled()) await downloadCore(onProgress: (x, s) => onProgress?.call(x * 0.5, s));
    final l = await lock();
    final fromLock = <String>[];
    final fromPypi = <String>[];
    for (final n in names) {
      final k = await lockName(n);
      if (k != null) {
        fromLock.add(k);
      } else {
        fromPypi.add(n);
      }
    }
    // PyPI packages: pure-Python wheels, and what they need.
    final notFound = <String>[];
    final pypiWheels = <(String, Uri, String)>[]; // name, url, file
    final pypiSeen = <String>{};
    final queue = [...fromPypi];
    while (queue.isNotEmpty) {
      final name = queue.removeAt(0);
      if (!pypiSeen.add(norm(name))) continue;
      onProgress?.call(0, 'Looking up $name on PyPI…');
      final found = await _pypiWheel(name);
      if (found == null) {
        notFound.add(name);
        continue;
      }
      pypiWheels.add((found.name, found.url, found.file));
      for (final dep in found.requires) {
        final k = await lockName(dep);
        if (k != null) {
          fromLock.add(k);
        } else if (!await _pypiHas(dep)) {
          queue.add(dep);
        }
      }
    }
    final wanted = await closure(fromLock);
    final todo = <PyodidePackage>[];
    for (final n in wanted) {
      final pkg = l[n]!;
      if (!await _isDownloaded(pkg)) todo.add(pkg);
    }
    final pypiTodo = <(String, Uri, String)>[];
    for (final w in pypiWheels) {
      if (!await File(p.join((await _pypiDir()).path, w.$3)).exists()) pypiTodo.add(w);
    }
    final count = todo.length + pypiTodo.length;
    var i = 0;
    final d = await dir();
    for (final pkg in todo) {
      final start = i / (count == 0 ? 1 : count);
      await _get(Uri.parse('$_cdn${pkg.file}'), File(p.join(d.path, pkg.file)),
          (x) => onProgress?.call(start + x / count, 'Downloading ${pkg.name} ${pkg.version}…'));
      i++;
    }
    final pd = await _pypiDir();
    for (final w in pypiTodo) {
      final start = i / (count == 0 ? 1 : count);
      await _get(w.$2, File(p.join(pd.path, w.$3)),
          (x) => onProgress?.call(start + x / count, 'Downloading ${w.$1} from PyPI…'));
      i++;
    }
    onProgress?.call(1, count == 0 ? 'Already downloaded.' : 'Downloaded $count package${count == 1 ? '' : 's'}.');
    notifyListeners();
    return notFound;
  }

  Future<bool> _pypiHas(String name) async {
    final n = norm(name);
    for (final f in await (await _pypiDir()).list().toList()) {
      if (f is File && norm(p.basename(f.path).split('-').first) == n) return true;
    }
    return false;
  }

  /// The newest wheel of [name] on PyPI that runs in Pyodide: pure Python,
  /// or built for this Pyodide.
  Future<({String name, Uri url, String file, List<String> requires})?> _pypiWheel(String name) async {
    try {
      final res = await http.get(Uri.parse('https://pypi.org/pypi/${Uri.encodeComponent(name)}/json'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final data = json.decode(res.body) as Map<String, dynamic>;
      final urls = (data['urls'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic>? pick;
      for (final u in urls) {
        final f = '${u['filename']}';
        if (f.endsWith('-py3-none-any.whl') || f.endsWith('-py2.py3-none-any.whl') || f.contains(_platformTag)) {
          pick = u;
          if (f.contains(_platformTag)) break;
        }
      }
      if (pick == null) return null;
      final info = data['info'] as Map<String, dynamic>;
      final requires = <String>[];
      for (final r in (info['requires_dist'] as List? ?? const [])) {
        final req = '$r';
        // Skip optional extras and requirements for other systems.
        if (req.contains('extra ==') || req.contains('platform_system') || req.contains('sys_platform')) continue;
        final m = RegExp(r'^([A-Za-z0-9][A-Za-z0-9._-]*)').firstMatch(req.trim());
        if (m != null) requires.add(m.group(1)!);
      }
      return (name: '${info['name'] ?? name}', url: Uri.parse('${pick['url']}'), file: '${pick['filename']}', requires: requires);
    } catch (_) {
      return null;
    }
  }

  Future<void> _get(Uri url, File to, void Function(double) onProgress) async {
    final part = File('${to.path}.part');
    await Runtimes.instance.downloadFile(url, part, onProgress);
    if (await to.exists()) await to.delete();
    await part.rename(to.path);
  }

  /// What's downloaded, for Settings (only packages you chose, plus what
  /// they need).
  Future<List<DownloadedPackage>> downloaded() async {
    final l = await lock();
    final d = await dir();
    final out = <DownloadedPackage>[];
    for (final pkg in l.values) {
      final f = File(p.join(d.path, pkg.file));
      if (pkg.file.isNotEmpty && await f.exists()) out.add(DownloadedPackage(pkg.name, pkg.version, await f.length()));
    }
    for (final f in await (await _pypiDir()).list().toList()) {
      if (f is! File || !f.path.endsWith('.whl')) continue;
      final parts = p.basename(f.path).split('-');
      out.add(DownloadedPackage(parts.first, parts.length > 1 ? parts[1] : '', await f.length(), fromPypi: true));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> removePackage(DownloadedPackage pkg) async {
    if (pkg.fromPypi) {
      for (final f in await (await _pypiDir()).list().toList()) {
        if (f is File && norm(p.basename(f.path).split('-').first) == norm(pkg.name)) await f.delete();
      }
    } else {
      final l = await lock();
      final file = l[pkg.name]?.file;
      if (file != null && file.isNotEmpty) {
        final f = File(p.join((await dir()).path, file));
        if (await f.exists()) await f.delete();
      }
    }
    notifyListeners();
  }

  /// Removes Python for phones and every package.
  Future<void> removeAll() async {
    stopAll();
    final d = await dir();
    if (await d.exists()) await d.delete(recursive: true);
    _lock = null;
    notifyListeners();
  }

  // ---------- the local server ----------

  /// Serves the page, the worker, the helpers and the downloaded files.
  /// The isolation headers turn on shared memory (Interrupt and input()).
  Future<void> handle(HttpRequest req, HttpResponse res, List<String> path) async {
    res.headers
      ..set('Cross-Origin-Opener-Policy', 'same-origin')
      ..set('Cross-Origin-Embedder-Policy', 'require-corp')
      ..set('Cross-Origin-Resource-Policy', 'same-origin');
    final name = path.join('/');
    switch (name) {
      case 'host.html':
        res.headers.contentType = ContentType.html;
        res.write(pyodideHostHtml);
        return;
      case 'worker.js':
        res.headers.contentType = ContentType('text', 'javascript', charset: 'utf-8');
        res.write(pyodideWorkerJs);
        return;
      case 'helpers.json':
        res.headers.contentType = ContentType.json;
        res.write(json.encode(pythonHelpers));
        return;
      case 'state.json':
        res.headers.contentType = ContentType.json;
        res.write(json.encode(await _state()));
        return;
    }
    if (path.length >= 2 && path.first == 'files') {
      final rel = path.sublist(1);
      if (rel.any((s) => s.isEmpty || s == '..' || s.startsWith('.'))) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      final root = await dir();
      final file = File(p.joinAll([root.path, ...rel]));
      if (!p.isWithin(root.path, file.path) || !await file.exists()) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      res.headers.contentType = _type(file.path);
      res.headers.contentLength = await file.length();
      await res.addStream(file.openRead());
      return;
    }
    res.statusCode = HttpStatus.notFound;
  }

  static ContentType _type(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.wasm' => ContentType('application', 'wasm'),
      '.mjs' || '.js' => ContentType('text', 'javascript', charset: 'utf-8'),
      '.json' => ContentType.json,
      _ => ContentType.binary,
    };
  }

  Future<Map<String, Object?>> _state() async {
    final l = await lock();
    final d = await dir();
    final packages = <String>[];
    for (final pkg in l.values) {
      if (pkg.file.isNotEmpty && await File(p.join(d.path, pkg.file)).exists()) packages.add(pkg.name);
    }
    final pypi = <Map<String, Object?>>[];
    for (final f in await (await _pypiDir()).list().toList()) {
      if (f is File && f.path.endsWith('.whl')) {
        pypi.add({'name': p.basename(f.path).split('-').first, 'file': p.basename(f.path), 'lockDeps': const <String>[]});
      }
    }
    return {'packages': packages, 'pypi': pypi};
  }

  // ---------- the web view ----------

  /// The web view that runs the workers. [PyodideHost] shows it (1×1,
  /// invisible) once the first kernel starts.
  final controller = ValueNotifier<WebViewController?>(null);
  Completer<void>? _hostReady;
  bool isolated = false;
  final _listeners = <String, void Function(Map<String, dynamic>)>{};

  Future<void> _ensureHost() async {
    if (_hostReady != null) return _hostReady!.future;
    final ready = _hostReady = Completer<void>();
    final url = await MiniAppServer.instance.pyodidePage();
    if (url == null) {
      _hostReady = null;
      throw RuntimeException("Python couldn't start: CodeNote's local server isn't running.");
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CodeNoteKernel', onMessageReceived: (m) => _onMessage(m.message));
    controller.value = c;
    await c.loadRequest(url);
    await ready.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _hostReady = null;
      controller.value = null;
      throw RuntimeException("Python couldn't start in this phone's web view. Update Android System WebView and try again.");
    });
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (m['t'] == 'host') {
      isolated = m['isolated'] == true;
      if (!(_hostReady?.isCompleted ?? true)) _hostReady!.complete();
      LogService().log('Pyodide: host ready (isolated: $isolated)');
      return;
    }
    final id = m['kernel'];
    if (id is String) _listeners[id]?.call(m);
  }

  Future<void> send(Map<String, Object?> message) async {
    await _ensureHost();
    await controller.value?.runJavaScript('codenote.receive(${json.encode(message)});');
  }

  void listen(String kernel, void Function(Map<String, dynamic>) onMessage) => _listeners[kernel] = onMessage;
  void forget(String kernel) => _listeners.remove(kernel);

  void stopAll() {
    for (final id in _listeners.keys.toList()) {
      unawaited(send({'op': 'stop', 'kernel': id}).catchError((_) {}));
    }
    _listeners.clear();
  }
}
