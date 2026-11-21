import 'dart:async';
import 'dart:convert';
import 'dart:ui' show TextRange;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Finds web links in plain text.
class LinkFinder {
  LinkFinder._();

  static final _pattern = RegExp(
    r'''(?:https?://|www\.)[^\s<>"'`]+''',
    caseSensitive: false,
  );

  /// Where each link is in [text], without trailing punctuation like the
  /// dot at the end of a sentence or a closing bracket that wasn't opened.
  static List<TextRange> ranges(String text) {
    final out = <TextRange>[];
    for (final m in _pattern.allMatches(text)) {
      var end = m.end;
      while (end > m.start) {
        final c = text[end - 1];
        if ('.,;:!?\'"*_~'.contains(c)) {
          end--;
          continue;
        }
        if (c == ')' || c == ']' || c == '}') {
          final open = c == ')' ? '(' : (c == ']' ? '[' : '{');
          final part = text.substring(m.start, end);
          if (open.allMatches(part).length < c.allMatches(part).length) {
            end--;
            continue;
          }
        }
        break;
      }
      // "https://" alone, or "www." alone, is not a link yet.
      final link = text.substring(m.start, end);
      final rest = link.replaceFirst(RegExp(r'^(https?://|www\.)', caseSensitive: false), '');
      if (rest.isEmpty || !rest.contains(RegExp(r'[a-zA-Z0-9]'))) continue;
      out.add(TextRange(start: m.start, end: end));
    }
    return out;
  }

  /// The links in [text], each once, in order, as full addresses
  /// (`www.x.com` becomes `https://www.x.com`).
  static List<String> urls(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in ranges(text)) {
      final url = normalize(r.textInside(text));
      if (seen.add(url)) out.add(url);
    }
    return out;
  }

  static String normalize(String link) =>
      link.toLowerCase().startsWith('www.') ? 'https://$link' : link;

  /// `github.com` for `https://www.github.com/a/b`.
  static String domain(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

/// What a page says about itself: title, short description and picture.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
    this.site,
  });

  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? site;

  bool get isEmpty =>
      (title ?? '').isEmpty && (description ?? '').isEmpty && (image ?? '').isEmpty;

  Map<String, dynamic> toMap() => {
        'url': url,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (image != null) 'image': image,
        if (site != null) 'site': site,
      };

  static LinkPreview fromMap(Map map) => LinkPreview(
        url: '${map['url']}',
        title: map['title'] as String?,
        description: map['description'] as String?,
        image: map['image'] as String?,
        site: map['site'] as String?,
      );

  /// Reads the Open Graph / Twitter / plain HTML tags of a page.
  static LinkPreview fromHtml(String url, String html) {
    final head = html.length > 200000 ? html.substring(0, 200000) : html;
    final metas = <String, String>{};
    for (final m in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(head)) {
      final tag = m.group(0)!;
      final key = _attr(tag, 'property') ?? _attr(tag, 'name') ?? _attr(tag, 'itemprop');
      final content = _attr(tag, 'content');
      if (key == null || content == null || content.trim().isEmpty) continue;
      metas.putIfAbsent(key.toLowerCase(), () => _clean(content));
    }
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = metas[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    var title = pick(['og:title', 'twitter:title', 'title']);
    if (title == null) {
      final t = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(head);
      if (t != null) title = _clean(t.group(1)!);
    }
    var image = pick(['og:image:secure_url', 'og:image', 'og:image:url', 'twitter:image', 'twitter:image:src', 'image']);
    if (image != null) image = _absolute(url, image);
    return LinkPreview(
      url: url,
      title: (title ?? '').isEmpty ? null : _cut(title!, 200),
      description: _cutOrNull(pick(['og:description', 'twitter:description', 'description']), 300),
      image: image,
      site: _cutOrNull(pick(['og:site_name', 'application-name']), 80),
    );
  }

  static String? _attr(String tag, String name) {
    final m = RegExp('\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false)
        .firstMatch(tag);
    if (m == null) return null;
    return m.group(2) ?? m.group(3) ?? m.group(4);
  }

  static String? _absolute(String base, String link) {
    final b = Uri.tryParse(base);
    final l = Uri.tryParse(link.trim());
    if (b == null || l == null) return null;
    final full = b.resolveUri(l);
    return full.scheme == 'http' || full.scheme == 'https' ? full.toString() : null;
  }

  static String? _cutOrNull(String? s, int max) => (s == null || s.isEmpty) ? null : _cut(s, max);
  static String _cut(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  static String _clean(String s) => decodeEntities(s).replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _named = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", '#39': "'",
    'nbsp': ' ', 'ndash': '–', 'mdash': '—', 'hellip': '…', 'rsquo': '’',
    'lsquo': '‘', 'rdquo': '”', 'ldquo': '“', 'middot': '·', 'copy': '©',
  };

  /// `&amp;` → `&`, `&#39;` → `'`, `&#x2F;` → `/`.
  static String decodeEntities(String s) =>
      s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
        final e = m.group(1)!;
        if (e.startsWith('#x') || e.startsWith('#X')) {
          final code = int.tryParse(e.substring(2), radix: 16);
          return code == null ? m.group(0)! : String.fromCharCode(code);
        }
        if (e.startsWith('#')) {
          final code = int.tryParse(e.substring(1));
          return code == null ? m.group(0)! : String.fromCharCode(code);
        }
        return _named[e.toLowerCase()] ?? m.group(0)!;
      });
}

/// Gets link previews and keeps them on this device, so each page is asked
/// once a week at most. Settings > Link previews turns it off: then CodeNote
/// never contacts the sites, and links are only highlighted.
class LinkPreviewService extends ChangeNotifier {
  LinkPreviewService._();
  static final instance = LinkPreviewService._();

  static const _boxName = 'link_previews';
  static const _enabledKey = '_enabled';
  static const _keep = Duration(days: 7);
  static const _keepFailed = Duration(days: 1);
  static const _maxBytes = 512 * 1024;
  static const _maxAtOnce = 4;

  final _pending = <String, Future<LinkPreview?>>{};
  final _memory = <String, LinkPreview?>{};
  bool? _enabled;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<Box> _box() => Hive.isBoxOpen(_boxName) ? Future.value(Hive.box(_boxName)) : Hive.openBox(_boxName);

  /// On unless the person turned it off.
  bool get enabled => _enabled ?? true;

  Future<void> load() async {
    if (_enabled != null) return;
    try {
      _enabled = (await _box()).get(_enabledKey) != false;
    } catch (_) {
      _enabled = true;
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    notifyListeners();
    try {
      await (await _box()).put(_enabledKey, on);
    } catch (_) {}
  }

  /// Forgets every saved preview.
  Future<void> clear() async {
    _pending.clear();
    _memory.clear();
    try {
      final box = await _box();
      final keys = box.keys.where((k) => k != _enabledKey).toList();
      await box.deleteAll(keys);
    } catch (_) {}
    notifyListeners();
  }

  /// The preview saved earlier, without waiting (null if none yet).
  LinkPreview? cached(String url) => _memory[url];

  /// The preview for [url], or null if the page has none or can't be
  /// reached. Asks the site only when there's no recent saved copy.
  Future<LinkPreview?> get(String url) {
    if (!enabled || kIsWeb) return Future.value(null);
    if (_memory.containsKey(url)) return Future.value(_memory[url]);
    return _pending[url] ??= _load(url).whenComplete(() => _pending.remove(url));
  }

  Future<LinkPreview?> _load(String url) async {
    Box? box;
    try {
      box = await _box();
      final saved = box.get(url);
      if (saved is Map) {
        final at = DateTime.fromMillisecondsSinceEpoch((saved['at'] as int?) ?? 0);
        final failed = saved['failed'] == true;
        if (DateTime.now().difference(at) < (failed ? _keepFailed : _keep)) {
          return _memory[url] = failed ? null : LinkPreview.fromMap(saved);
        }
      }
    } catch (_) {}

    await _turn();
    LinkPreview? preview;
    try {
      preview = await _fetch(url);
    } catch (_) {
      preview = null;
    } finally {
      _done();
    }
    if (preview != null && preview.isEmpty) preview = null;
    _memory[url] = preview;
    try {
      await box?.put(url, {
        ...?preview?.toMap(),
        'at': DateTime.now().millisecondsSinceEpoch,
        if (preview == null) 'failed': true,
      });
    } catch (_) {}
    return preview;
  }

  Future<LinkPreview?> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.addAll({
          // Many sites only give their preview tags to link-preview bots.
          'User-Agent': 'Mozilla/5.0 (compatible; CodeNote link preview; +https://mahmoudyosrimahmoud13.github.io/code_note)',
          'Accept': 'text/html,application/xhtml+xml;q=0.9,image/*;q=0.8,*/*;q=0.5',
        });
      final response = await client.send(request).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400) return null;
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (type.startsWith('image/')) {
        return LinkPreview(url: url, image: url, title: uri.pathSegments.isEmpty ? null : uri.pathSegments.last);
      }
      if (type.isNotEmpty && !type.contains('html')) return null;
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxBytes) break;
        // The tags are in <head>: stop early once it's over.
        if (bytes.length > 16384 && latin1.decode(chunk, allowInvalid: true).toLowerCase().contains('</head>')) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);
      return LinkPreview.fromHtml(url, html);
    } finally {
      client.close();
    }
  }

  Future<void> _turn() async {
    if (_running < _maxAtOnce) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  void _done() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }
}
