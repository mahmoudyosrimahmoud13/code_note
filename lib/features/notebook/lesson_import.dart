import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/util/code_languages.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';

/// Lessons from inPace (and any Markdown file) as notes: text becomes
/// Markdown blocks and every ``` fence a code block you can run.
///
/// The format is in the Project doc claude/codenote-inpace-bridge.md.
class LessonImport {
  LessonImport._();

  static const _uuid = Uuid();

  /// The link inPace makes, `codenote://open/BODY`, and the web fallback
  /// `https://…/code_note/open#BODY`.
  static bool isLink(String text) {
    final t = text.trim();
    return t.startsWith('codenote://') || (t.contains('/code_note/open#') && t.startsWith('http'));
  }

  /// The JSON inside a link: zlib-compressed, URL-safe base64 without
  /// padding (the same as inPace's own links). Null if it isn't one.
  static Map<String, dynamic>? decodeLink(String link) {
    final t = link.trim();
    String body;
    if (t.startsWith('codenote://open/')) {
      body = t.substring('codenote://open/'.length);
    } else if (t.startsWith('codenote://open?')) {
      body = Uri.parse(t).queryParameters['d'] ?? '';
    } else if (t.contains('#')) {
      body = t.substring(t.indexOf('#') + 1);
    } else {
      return null;
    }
    body = Uri.decodeComponent(body).replaceAll(RegExp(r'\s'), '');
    if (body.isEmpty) return null;
    try {
      final padded = body.padRight(body.length + (4 - body.length % 4) % 4, '=');
      final raw = ZLibCodec().decode(base64Url.decode(padded));
      final data = json.decode(utf8.decode(raw));
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  /// The other way, for tests and the web fallback page.
  static String encodeLink(Map<String, dynamic> payload) {
    final raw = utf8.encode(json.encode(payload));
    final body = base64Url.encode(ZLibCodec(level: 9).encode(raw)).replaceAll('=', '');
    return 'codenote://open/$body';
  }

  /// YAML front matter at the top of a `.md` file. inPace writes each
  /// value as JSON (which is valid YAML); plain words work too.
  static (Map<String, dynamic>, String) frontMatter(String text) {
    final t = text.startsWith('﻿') ? text.substring(1) : text;
    if (!t.startsWith('---')) return (const {}, t);
    final lines = const LineSplitter().convert(t);
    if (lines.isEmpty || lines.first.trim() != '---') return (const {}, t);
    final end = lines.indexWhere((l) => l.trim() == '---' || l.trim() == '...', 1);
    if (end < 0) return (const {}, t);
    final meta = <String, dynamic>{};
    for (final line in lines.sublist(1, end)) {
      final colon = line.indexOf(':');
      if (colon <= 0 || line.startsWith(' ')) continue;
      final key = line.substring(0, colon).trim();
      final raw = line.substring(colon + 1).trim();
      Object? value = raw;
      try {
        value = json.decode(raw);
      } catch (_) {
        if (raw.length >= 2 && (raw.startsWith("'") && raw.endsWith("'") || raw.startsWith('"') && raw.endsWith('"'))) {
          value = raw.substring(1, raw.length - 1);
        } else if (int.tryParse(raw) != null) {
          value = int.parse(raw);
        }
      }
      meta[key] = value;
    }
    return (meta, lines.sublist(end + 1).join('\n'));
  }

  /// Fence names that are text, not code to run: they stay in the Markdown.
  static const _plainFences = {'text', 'txt', 'plain', 'plaintext', 'output', 'console', 'mermaid', 'diff', 'log', 'none'};

  static const _aliases = <String, Language>{
    'py': Language.python, 'python3': Language.python, 'ipython': Language.python,
    'js': Language.javaScript, 'node': Language.javaScript, 'jsx': Language.javaScript, 'mjs': Language.javaScript,
    'ts': Language.typeScript, 'tsx': Language.typeScript,
    'sh': Language.bash, 'shell': Language.bash, 'zsh': Language.bash, 'bash': Language.bash,
    'ps': Language.powershell, 'ps1': Language.powershell, 'pwsh': Language.powershell,
    'yml': Language.yaml, 'c++': Language.cpp, 'cc': Language.cpp, 'cxx': Language.cpp, 'h': Language.c,
    'cs': Language.cSharp, 'csharp': Language.cSharp, 'c#': Language.cSharp,
    'golang': Language.go, 'kt': Language.kotlin, 'rb': Language.ruby, 'rs': Language.rust,
    'dockerfile': Language.docker, 'postgres': Language.pgSql, 'postgresql': Language.pgSql,
    'jl': Language.julia, 'md': Language.markdown, 'objc': Language.objectiveC,
  };

  static Map<String, Language>? _names;

  /// The language for a fence name (```py, ```JavaScript), or null when
  /// it isn't one CodeNote knows.
  static Language? languageFor(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    final alias = _aliases[n];
    if (alias != null) return alias;
    _names ??= () {
      final m = <String, Language>{};
      for (final l in Language.values) {
        if (l == Language.none) continue;
        final info = languageInfo(l);
        for (final key in [l.name, info.short, info.extension, info.label, ...info.otherExtensions]) {
          m.putIfAbsent(key.toLowerCase(), () => l);
        }
      }
      return m;
    }();
    return _names![n];
  }

  /// Images with a relative path point at files inside the course, which
  /// CodeNote doesn't have: they're dropped. Web images stay.
  static String _dropLocalImages(String md) =>
      md.replaceAll(RegExp(r'!\[[^\]]*\]\((?!https?://)[^)]*\)'), '');

  /// Blocks for a lesson's Markdown.
  static List<BlockEntity> blocks(String markdown, {Language fallback = Language.python}) {
    final out = <BlockEntity>[];
    final text = <String>[];
    void flush() {
      final t = _dropLocalImages(text.join('\n')).trim();
      text.clear();
      if (t.isNotEmpty) out.add(MarkdownBlockEntity(id: _uuid.v4(), text: t));
    }

    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final open = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*([^\s`{]*)');
    var i = 0;
    while (i < lines.length) {
      final m = open.firstMatch(lines[i]);
      if (m == null) {
        text.add(lines[i]);
        i++;
        continue;
      }
      final fence = m.group(1)!;
      final name = m.group(2) ?? '';
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length) {
        final t = lines[j].trim();
        if (t.startsWith(fence[0] * fence.length) && t.replaceAll(fence[0], '').isEmpty) break;
        body.add(lines[j]);
        j++;
      }
      final plain = _plainFences.contains(name.toLowerCase());
      final language = name.isEmpty ? fallback : languageFor(name);
      if (plain || language == null || language == Language.markdown) {
        // Keep it as it was, inside the text.
        text.addAll(lines.sublist(i, j < lines.length ? j + 1 : j));
      } else {
        flush();
        out.add(CodeBlockEntity(id: _uuid.v4(), text: body.join('\n'), language: language));
      }
      i = j + 1;
    }
    flush();
    return out;
  }
}
