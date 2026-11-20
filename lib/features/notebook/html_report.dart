import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/note.dart';

/// A note as one HTML file to share: text, code, tables and the plots
/// saved under the blocks, with pictures inside the file. Opens in any
/// browser and prints well.
class HtmlReport {
  HtmlReport._();

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static String fromNote(NoteEntity note, {List<int>? Function(String path)? readImage}) {
    final body = StringBuffer();
    for (final b in note.blocks) {
      final text = b.text ?? '';
      if (b is CodeBlockEntity) {
        if (text.trim().isEmpty) continue;
        body.writeln('<pre class="code"><span class="lang">${_esc(b.language.name)}</span>'
            '<code>${_esc(text)}</code></pre>');
      } else if (b is ImageBlockEntity) {
        final path = b.imagePath ?? '';
        final bytes = readImage?.call(path);
        if (bytes == null) continue;
        final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
        final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : (ext == 'gif' ? 'image/gif' : 'image/png');
        body.writeln('<figure><img src="data:$mime;base64,${base64Encode(bytes)}" alt=""></figure>');
      } else if (text.trim().isNotEmpty) {
        body.writeln(md.markdownToHtml(text, extensionSet: md.ExtensionSet.gitHubWeb));
      }
    }
    final title = _esc(note.title.trim().isEmpty ? 'Report' : note.title.trim());
    final date = note.lastModified.toIso8601String().substring(0, 10);
    return '''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
  body { font: 16px/1.6 -apple-system, "Segoe UI", Roboto, Inter, sans-serif; color: #1d1b26; background: #fbfaff;
         max-width: 920px; margin: 0 auto; padding: 40px 22px 80px; }
  h1, h2, h3 { line-height: 1.25; } header h1 { margin: 0; font-size: 34px; }
  header p { color: #6b6880; margin: 6px 0 30px; font-size: 14px; }
  pre.code { background: #16141f; color: #e8e6f3; padding: 16px 18px; border-radius: 12px; overflow-x: auto;
             font: 13.5px/1.6 "JetBrains Mono", ui-monospace, Menlo, Consolas, monospace; position: relative; }
  pre.code .lang { position: absolute; top: 6px; right: 12px; font-size: 11px; color: #8d89a6; }
  code { font-family: "JetBrains Mono", ui-monospace, Menlo, Consolas, monospace; font-size: .92em; }
  :not(pre) > code { background: #efecfa; padding: 1px 6px; border-radius: 5px; }
  table { border-collapse: collapse; margin: 14px 0; font-size: 14px; display: block; overflow-x: auto; }
  th, td { border-bottom: 1px solid #e3e0ef; padding: 6px 12px; text-align: right; }
  th:first-child, td:first-child { text-align: left; } th { background: #f1eefb; }
  figure { margin: 16px 0; } img { max-width: 100%; border-radius: 10px; border: 1px solid #e3e0ef; background: #fff; }
  blockquote { border-left: 4px solid #7b5cff; margin: 0; padding: 4px 16px; color: #4a4760; }
  footer { margin-top: 50px; color: #8d89a6; font-size: 13px; }
  @media print { body { background: #fff; } pre.code { white-space: pre-wrap; } }
</style></head>
<body>
<header><h1>$title</h1><p>$date</p></header>
$body
<footer>Made with CodeNote</footer>
</body></html>
''';
  }

  /// Reads image files for the report.
  static List<int>? readFile(String path) {
    try {
      return File(path).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }
}
