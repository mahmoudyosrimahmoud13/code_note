import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/util/code_languages.dart';
import '../../helpers/helper_methods.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';

class GistException implements Exception {
  GistException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns GitHub Gists into notes and notes into Gists.
/// Import works for any public gist with no sign-in. Export needs a GitHub
/// token with the "gist" permission, kept only on this device.
class GistService {
  GistService._();
  static final GistService instance = GistService._();

  static const _api = 'https://api.github.com';
  static const _boxName = 'appBox';
  static const _tokenKey = 'GITHUB_GIST_TOKEN';

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  Future<String> loadToken() async => ((await _box()).get(_tokenKey) as String?) ?? '';
  Future<void> saveToken(String token) async => (await _box()).put(_tokenKey, token.trim());

  /// The gist id from a link like https://gist.github.com/user/abc123,
  /// a raw link, or the bare id. Null if nothing looks like an id.
  static String? parseId(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final parts = (uri != null && uri.host.isNotEmpty)
        ? uri.pathSegments.where((p) => p.isNotEmpty).toList()
        : [text];
    for (final p in parts.reversed) {
      final clean = p.split('#').first;
      if (RegExp(r'^[0-9a-fA-F]{20,40}$').hasMatch(clean)) return clean;
    }
    return null;
  }

  /// Builds a note from a gist's JSON (as GitHub returns it).
  static NoteEntity noteFromGistJson(Map<String, dynamic> gist) {
    final files = (gist['files'] as Map<String, dynamic>? ?? {});
    final description = (gist['description'] as String? ?? '').trim();
    final names = files.keys.toList()..sort();
    final blocks = <BlockEntity>[];
    for (final name in names) {
      final file = files[name] as Map<String, dynamic>;
      final content = file['content'] as String? ?? '';
      final lang = languageForFileName(name);
      final lower = name.toLowerCase();
      if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
        blocks.add(MarkdownBlockEntity(id: uuid.generate(), text: content));
      } else {
        blocks
          ..add(MarkdownBlockEntity(id: uuid.generate(), text: '`$name`'))
          ..add(CodeBlockEntity(id: uuid.generate(), text: content, language: lang));
      }
    }
    final url = gist['html_url'] as String?;
    if (url != null) {
      blocks.add(NoteBlockEntity(id: uuid.generate(), text: 'Imported from $url'));
    }
    return NoteEntity(
      id: uuid.generate(),
      title: description.isNotEmpty ? description : (names.isEmpty ? 'Gist' : names.first),
      tags: const ['gist'],
      lastModified: DateTime.now(),
      blocks: blocks,
    );
  }

  /// Gist files from a note: one file per code block, plus a README.md
  /// with the text and markdown. Images are skipped.
  static Map<String, String> filesFromNote(NoteEntity note) {
    final files = <String, String>{};
    final readme = StringBuffer();
    final base = _slug(note.title);
    var n = 0;
    for (final b in note.blocks) {
      if (b is CodeBlockEntity) {
        final text = b.text ?? '';
        if (text.trim().isEmpty) continue;
        n++;
        final ext = b.language == Language.none ? 'txt' : languageInfo(b.language).extension;
        var name = n == 1 ? '$base.$ext' : '$base-$n.$ext';
        while (files.containsKey(name)) {
          name = '_$name';
        }
        files[name] = text;
      } else if (b is! ImageBlockEntity) {
        final text = (b.text ?? '').trim();
        if (text.isNotEmpty) readme.writeln('$text\n');
      }
    }
    final readmeText = readme.toString().trim();
    if (readmeText.isNotEmpty || files.isEmpty) {
      final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
      files['README.md'] = '# $title\n\n$readmeText\n';
    }
    return files;
  }

  static String _slug(String title) {
    final s = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.isEmpty) return 'snippet';
    return s.length > 40 ? s.substring(0, 40) : s;
  }

  Map<String, String> _headers([String? token]) => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// Downloads a gist and returns it as a new (not yet saved) note.
  Future<NoteEntity> importGist(String linkOrId) async {
    final id = parseId(linkOrId);
    if (id == null) throw GistException("That doesn't look like a gist link or id.");
    final token = await loadToken();
    final http.Response res;
    try {
      res = await http
          .get(Uri.parse('$_api/gists/$id'), headers: _headers(token))
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw GistException('GitHub took too long to answer. Try again.');
    } catch (_) {
      throw GistException("Couldn't reach GitHub. Check your internet connection.");
    }
    if (res.statusCode == 404) throw GistException('No gist found with that id.');
    if (res.statusCode == 403) {
      throw GistException('GitHub says slow down (rate limit). Try again in a few minutes.');
    }
    if (res.statusCode != 200) throw GistException('GitHub answered ${res.statusCode}.');
    final gist = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    // Big files come back cut short; fetch the full text.
    final files = gist['files'] as Map<String, dynamic>? ?? {};
    for (final f in files.values.cast<Map<String, dynamic>>()) {
      if (f['truncated'] == true && f['raw_url'] is String) {
        try {
          final raw = await http.get(Uri.parse(f['raw_url'] as String))
              .timeout(const Duration(seconds: 30));
          if (raw.statusCode == 200) f['content'] = utf8.decode(raw.bodyBytes);
        } catch (_) {}
      }
    }
    return noteFromGistJson(gist);
  }

  /// Uploads [note] as a new gist (secret by default) and returns its link.
  Future<String> exportNote(NoteEntity note, {bool public = false}) async {
    final token = await loadToken();
    if (token.isEmpty) throw GistException('Add a GitHub token first.');
    final body = json.encode({
      'description': note.title.trim().isEmpty ? 'From CodeNote' : note.title.trim(),
      'public': public,
      'files': {
        for (final e in filesFromNote(note).entries) e.key: {'content': e.value},
      },
    });
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('$_api/gists'), headers: _headers(token), body: body)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw GistException('GitHub took too long to answer. Try again.');
    } catch (_) {
      throw GistException("Couldn't reach GitHub. Check your internet connection.");
    }
    if (res.statusCode == 401) {
      throw GistException('GitHub rejected the token. Make a new one with the "gist" permission.');
    }
    if (res.statusCode != 201) throw GistException('GitHub answered ${res.statusCode}.');
    final out = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return out['html_url'] as String? ?? '';
  }
}
