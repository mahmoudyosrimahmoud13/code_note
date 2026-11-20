import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../core/services/log_service.dart';
import '../runner/sandbox.dart';
import 'mini_app_storage.dart';

/// A tiny web server inside CodeNote that runs notes as pages ("mini apps")
/// and lets them save data.
///
/// It only listens on this device (127.0.0.1), on a random port, and every
/// address includes a random secret, so other apps and websites can't reach
/// it. It starts the first time a note is run and stops with the app.
class MiniAppServer {
  MiniAppServer._();
  static final MiniAppServer instance = MiniAppServer._();

  HttpServer? _server;
  Future<HttpServer?>? _starting;
  final String _secret = _randomSecret();
  final _pages = <String, String>{};
  final _spaces = <String, String>{};

  static String _randomSecret() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Makes [document] runnable as note [noteId] and returns its address,
  /// or null if the server can't start (then the page runs without saving).
  /// [spaceKey] is the note's sandbox (shared by notes in one folder): the
  /// page can read its files and call servers started there.
  Future<Uri?> serve(String noteId, String document, {String? spaceKey}) async {
    final server = await (_starting ??= _start());
    if (server == null) {
      _starting = null; // try again next time
      return null;
    }
    _pages[noteId] = document;
    if (spaceKey != null) _spaces[noteId] = spaceKey;
    return Uri.parse('http://127.0.0.1:${server.port}/$_secret/app/${Uri.encodeComponent(noteId)}');
  }

  Future<HttpServer?> _start() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_handle, onError: (Object e) => LogService().log('MiniApp: [ERROR] $e'));
      LogService().log('MiniApp: [START] listening on port ${server.port}');
      return server;
    } catch (e) {
      LogService().log('MiniApp: [ERROR] could not start: $e');
      return null;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Cache-Control', 'no-store');
    try {
      final parts = req.uri.pathSegments;
      if (parts.length < 3 || parts[0] != _secret) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final kind = parts[1];
      if (kind == 'app' && parts.length == 3 && req.method == 'GET') {
        final noteId = parts[2];
        final doc = _pages[noteId];
        if (doc == null) {
          res.statusCode = HttpStatus.notFound;
          return;
        }
        final data = await MiniAppStorage.instance.load(noteId);
        final space = _spaces[noteId];
        res.headers.contentType = ContentType.html;
        res.write(injectBridge(
            doc,
            bridgeScript(
              data: data,
              dataUrl: '/$_secret/data/${Uri.encodeComponent(noteId)}',
              filesUrl: space == null ? null : '/$_secret/files/${Uri.encodeComponent(space)}/',
              proxyUrl: '/$_secret/proxy/',
            )));
      } else if (kind == 'data' && parts.length == 3 && req.method == 'POST') {
        final body = await utf8.decodeStream(req);
        final data = MiniAppStorage.decode(body);
        if (data == null || !await MiniAppStorage.instance.save(parts[2], data)) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
        res.statusCode = HttpStatus.noContent;
      } else if (kind == 'files' && parts.length >= 4 && req.method == 'GET') {
        await _sendFile(res, parts[2], parts.sublist(3));
      } else if (kind == 'proxy' && parts.length >= 3) {
        await _proxy(req, res, parts[2], parts.sublist(3));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      LogService().log('MiniApp: [ERROR] request failed: $e');
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close();
    }
  }

  /// Read-only: a file from a sandbox folder, never outside it.
  Future<void> _sendFile(HttpResponse res, String spaceKey, List<String> path) async {
    if (!_spaces.containsValue(spaceKey) ||
        path.any((part) => part.isEmpty || part == '..' || part.startsWith('.'))) {
      res.statusCode = HttpStatus.forbidden;
      return;
    }
    final root = await Sandbox.instance.space(spaceKey);
    final file = File(p.joinAll([root.path, ...path]));
    if (!p.isWithin(root.path, file.path) || !await file.exists()) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    res.headers.contentType = contentTypeFor(file.path);
    await res.addStream(file.openRead());
  }

  /// Forwards a page's request to a server running on this device (for
  /// example FastAPI on port 8000), so pages don't hit CORS errors.
  Future<void> _proxy(HttpRequest req, HttpResponse res, String portText, List<String> path) async {
    final port = int.tryParse(portText);
    if (port == null || port < 1024 || port > 65535) {
      res.statusCode = HttpStatus.badRequest;
      return;
    }
    final target = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: '/${path.join('/')}',
      query: req.uri.query.isEmpty ? null : req.uri.query,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final out = await client.openUrl(req.method, target);
      for (final h in ['content-type', 'accept', 'authorization']) {
        final v = req.headers.value(h);
        if (v != null) out.headers.set(h, v);
      }
      await out.addStream(req);
      final back = await out.close();
      res.statusCode = back.statusCode;
      final type = back.headers.contentType;
      if (type != null) res.headers.contentType = type;
      await res.addStream(back);
    } on SocketException {
      res.statusCode = HttpStatus.badGateway;
      res.write('Nothing is running on port $port. Start the server note first.');
    } finally {
      client.close();
    }
  }

  static ContentType contentTypeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.html' || '.htm' => ContentType.html,
      '.json' => ContentType.json,
      '.txt' || '.md' || '.csv' || '.log' || '.py' => ContentType.text,
      '.png' => ContentType('image', 'png'),
      '.jpg' || '.jpeg' => ContentType('image', 'jpeg'),
      '.gif' => ContentType('image', 'gif'),
      '.svg' => ContentType('image', 'svg+xml'),
      '.webp' => ContentType('image', 'webp'),
      '.mp3' => ContentType('audio', 'mpeg'),
      '.m4a' => ContentType('audio', 'mp4'),
      '.mp4' => ContentType('video', 'mp4'),
      '.webm' => ContentType('video', 'webm'),
      '.css' => ContentType('text', 'css', charset: 'utf-8'),
      '.js' => ContentType('text', 'javascript', charset: 'utf-8'),
      _ => ContentType.binary,
    };
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null;
  }

  /// The script added to every mini app. It loads the note's saved data and
  /// makes `localStorage` and `codenote.storage` save into CodeNote.
  /// `codenote.api(8000, '/todos')` reaches a server started in the same
  /// folder, and `codenote.file('chart.png')` a file it made.
  /// With [dataUrl] null, data lives only until the page closes.
  static String bridgeScript({
    required Map<String, String> data,
    String? dataUrl,
    String? filesUrl,
    String? proxyUrl,
  }) {
    // Safe inside a <script> tag: no "</script>" can sneak through.
    String js(Object? v) => json.encode(v).replaceAll('<', r'<');
    return '''<script>
(function () {
  var data = ${js(data)};
  var url = ${js(dataUrl)};
  var filesUrl = ${js(filesUrl)};
  var proxyUrl = ${js(proxyUrl)};
  var timer = null;
  function send(beacon) {
    if (!url) return;
    var body = JSON.stringify(data);
    if (beacon && navigator.sendBeacon) { navigator.sendBeacon(url, body); return; }
    fetch(url, { method: 'POST', body: body, keepalive: true }).catch(function () {});
  }
  function changed() { clearTimeout(timer); timer = setTimeout(send, 200); }
  function has(k) { return Object.prototype.hasOwnProperty.call(data, k); }
  var store = {
    getItem: function (k) { k = String(k); return has(k) ? data[k] : null; },
    setItem: function (k, v) { data[String(k)] = String(v); changed(); },
    removeItem: function (k) { delete data[String(k)]; changed(); },
    clear: function () { data = {}; changed(); },
    key: function (i) { var ks = Object.keys(data); return i < ks.length ? ks[i] : null; },
    get length() { return Object.keys(data).length; }
  };
  try { Object.defineProperty(window, 'localStorage', { value: store, configurable: true }); } catch (e) {}
  function clean(path) { return String(path || '').replace(/^\\/+/, ''); }
  window.codenote = {
    saves: !!url,
    storage: {
      get: function (k, fallback) {
        var v = store.getItem(k);
        if (v === null) return fallback === undefined ? null : fallback;
        try { return JSON.parse(v); } catch (e) { return v; }
      },
      set: function (k, v) { store.setItem(k, JSON.stringify(v)); },
      remove: function (k) { store.removeItem(k); },
      clear: function () { store.clear(); },
      keys: function () { return Object.keys(data); }
    },
    api: function (port, path) {
      return (proxyUrl ? proxyUrl + port + '/' : 'http://127.0.0.1:' + port + '/') + clean(path);
    },
    file: function (name) { return filesUrl ? filesUrl + clean(name) : null; }
  };
  addEventListener('pagehide', function () { if (timer) { clearTimeout(timer); send(true); } });
})();
</script>''';
  }

  /// Puts [script] at the very start of the page so it runs before the
  /// page's own code.
  static String injectBridge(String doc, String script) {
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(doc);
    if (head != null) return doc.replaceRange(head.end, head.end, '\n$script');
    final html = RegExp(r'<html[^>]*>', caseSensitive: false).firstMatch(doc);
    if (html != null) return doc.replaceRange(html.end, html.end, '\n<head>$script</head>');
    return '$script\n$doc';
  }
}
