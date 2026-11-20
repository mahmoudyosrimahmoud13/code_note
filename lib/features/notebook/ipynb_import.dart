import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/util/code_languages.dart';
import '../../core/util/image_helper.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';

/// Opens a Jupyter notebook (`.ipynb`) as a note: Markdown cells become
/// Markdown blocks, code cells become code blocks in the notebook's
/// language, and saved outputs (text, tables, plots, errors) come along
/// under their cell. Python notes then run like Jupyter in CodeNote.
class IpynbImport {
  IpynbImport._();

  static const _uuid = Uuid();
  static const _maxText = 20000;

  /// Quick check on the start of a file, for files without a name.
  static bool looksLikeNotebook(String head) {
    final t = head.trimLeft();
    return t.startsWith('{') && t.contains('"cells"') && t.contains('"cell_type"');
  }

  /// Reads the notebook at [path] into a new note (images are saved into
  /// CodeNote's own storage).
  static Future<NoteEntity> fromFile(String path) async {
    final text = await File(path).readAsString();
    final blocks = await toBlocks(text, saveImage: _saveImage);
    return NoteEntity(
      id: _uuid.v4(),
      title: p.basenameWithoutExtension(path),
      blocks: blocks.isEmpty ? [MarkdownBlockEntity(id: _uuid.v4(), text: '*This notebook is empty.*')] : blocks,
      lastModified: DateTime.now(),
      tags: const ['jupyter'],
    );
  }

  static Future<String> _saveImage(Uint8List bytes, String extension) async {
    final tmp = File(p.join(Directory.systemTemp.path, '${_uuid.v4()}.$extension'));
    await tmp.writeAsBytes(bytes);
    final saved = await ImageHelper.persistImage(tmp.path);
    try {
      await tmp.delete();
    } catch (_) {}
    return saved;
  }

  /// The blocks for notebook JSON [source]. [saveImage] stores a plot or
  /// picture and returns its path. Throws [FormatException] if it isn't a
  /// notebook.
  static Future<List<BlockEntity>> toBlocks(
    String source, {
    required Future<String> Function(Uint8List bytes, String extension) saveImage,
  }) async {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Not a Jupyter notebook');
    final metadata = _map(decoded['metadata']);
    final language = _language(metadata);

    // nbformat 4 keeps cells at the top; nbformat 3 inside worksheets.
    var cells = decoded['cells'];
    if (cells == null && decoded['worksheets'] is List && (decoded['worksheets'] as List).isNotEmpty) {
      cells = _map((decoded['worksheets'] as List).first)['cells'];
    }
    if (cells is! List) throw const FormatException('Not a Jupyter notebook');

    final blocks = <BlockEntity>[];
    for (final raw in cells) {
      final cell = _map(raw);
      final type = cell['cell_type'];
      final text = _text(cell['source'] ?? cell['input']);
      switch (type) {
        case 'markdown':
          if (text.trim().isNotEmpty) blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: text));
        case 'heading': // nbformat 3
          final level = (cell['level'] is int ? cell['level'] as int : 1).clamp(1, 6).toInt();
          blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: '${'#' * level} $text'));
        case 'raw':
          if (text.trim().isNotEmpty) blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: _fence(text)));
        case 'code':
          blocks.add(CodeBlockEntity(id: _uuid.v4(), text: text, language: language));
          final outputs = cell['outputs'];
          if (outputs is List) blocks.addAll(await _outputs(outputs, saveImage));
      }
    }
    return blocks;
  }

  static Language _language(Map<String, dynamic> metadata) {
    final info = _map(metadata['language_info']);
    final ext = info['file_extension'];
    if (ext is String && ext.isNotEmpty) {
      final found = languageForFileName('notebook${ext.startsWith('.') ? ext : '.$ext'}');
      if (found != Language.none) return found;
    }
    final name = (info['name'] ?? _map(metadata['kernelspec'])['language'] ?? 'python').toString().toLowerCase();
    return switch (name) {
      'python' || 'python3' => Language.python,
      'r' => Language.r,
      'bash' || 'sh' => Language.bash,
      'javascript' || 'node' => Language.javaScript,
      'typescript' => Language.typeScript,
      'dart' => Language.dart,
      'julia' || 'scala' || 'ruby' || 'go' || 'rust' || 'kotlin' || 'java' || 'sql' => languageForFileName('x.${_ext[name]}'),
      _ => Language.python,
    };
  }

  static const _ext = {
    'julia': 'jl', 'scala': 'scala', 'ruby': 'rb', 'go': 'go', 'rust': 'rs',
    'kotlin': 'kt', 'java': 'java', 'sql': 'sql',
  };

  /// Saved outputs, in order. Text next to each other is joined into one
  /// block, like CodeNote's own "Save output".
  static Future<List<BlockEntity>> _outputs(
    List outputs,
    Future<String> Function(Uint8List bytes, String extension) saveImage,
  ) async {
    final blocks = <BlockEntity>[];
    final text = StringBuffer();
    void flush() {
      final t = text.toString().trimRight();
      text.clear();
      if (t.isEmpty) return;
      blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: _fence(_cut(t))));
    }

    for (final raw in outputs) {
      final out = _map(raw);
      final type = out['output_type'];
      if (type == 'stream') {
        text.write(_text(out['text']));
        continue;
      }
      if (type == 'error' || type == 'pyerr') {
        final trace = out['traceback'];
        final t = trace is List ? trace.map((e) => '$e').join('\n') : '${out['ename']}: ${out['evalue']}';
        text.writeln(_stripAnsi(t));
        continue;
      }
      // execute_result / display_data (nbformat 3 keeps them flat).
      final data = out['data'] is Map ? _map(out['data']) : out;
      final png = data['image/png'] ?? data['png'];
      final jpeg = data['image/jpeg'] ?? data['jpeg'];
      final image = png ?? jpeg;
      if (image != null) {
        try {
          final bytes = base64Decode(_text(image).replaceAll(RegExp(r'\s'), ''));
          flush();
          final path = await saveImage(bytes, png != null ? 'png' : 'jpg');
          blocks.add(ImageBlockEntity(id: _uuid.v4(), imagePath: path));
          continue;
        } catch (_) {
          // Broken picture: fall through to the text version.
        }
      }
      final markdown = data['text/markdown'];
      if (markdown != null) {
        flush();
        blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: _text(markdown)));
        continue;
      }
      final plain = data['text/plain'] ?? data['text'];
      if (plain != null) {
        text.writeln(_text(plain));
      } else if (data['text/html'] != null) {
        text.writeln('(HTML output: run the block again to see it)');
      }
    }
    flush();
    return blocks;
  }

  static Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

  /// Notebook text is a string or a list of lines.
  static String _text(Object? v) => v is List ? v.map((e) => '$e').join() : (v?.toString() ?? '');

  static String _cut(String t) => t.length > _maxText ? '…\n${t.substring(t.length - _maxText)}' : t;

  static String _fence(String t) {
    var fence = '```';
    while (t.contains(fence)) {
      fence += '`';
    }
    return '${fence}text\n$t\n$fence';
  }

  static String _stripAnsi(String t) => t.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
}

/// Writes a note as a Jupyter notebook: Markdown blocks become Markdown
/// cells, code blocks code cells, pictures Markdown cells with the image
/// inside, so it opens in Jupyter, Colab and Kaggle.
class IpynbExport {
  IpynbExport._();

  static List<String> _lines(String text) {
    final parts = text.split('\n');
    return [for (var i = 0; i < parts.length; i++) i < parts.length - 1 ? '${parts[i]}\n' : parts[i]]
      ..removeWhere((l) => l.isEmpty);
  }

  static String fromNote(NoteEntity note, {Uint8List? Function(String path)? readImage}) {
    final code = note.blocks.whereType<CodeBlockEntity>().toList();
    final lang = code.isEmpty ? Language.python : code.first.language;
    final cells = <Map<String, Object?>>[];
    if (note.title.trim().isNotEmpty) {
      cells.add({'cell_type': 'markdown', 'metadata': {}, 'source': _lines('# ${note.title.trim()}')});
    }
    for (final b in note.blocks) {
      final text = b.text ?? '';
      if (b is CodeBlockEntity) {
        cells.add({
          'cell_type': 'code',
          'execution_count': null,
          'metadata': {},
          'outputs': [],
          'source': _lines(text),
        });
      } else if (b is ImageBlockEntity) {
        final bytes = readImage?.call(b.imagePath ?? '');
        if (bytes == null) continue;
        final ext = p.extension(b.imagePath ?? '').toLowerCase() == '.jpg' ? 'jpeg' : 'png';
        final name = 'image${cells.length}.${ext == 'jpeg' ? 'jpg' : 'png'}';
        cells.add({
          'cell_type': 'markdown',
          'metadata': {},
          'attachments': {
            name: {'image/$ext': base64Encode(bytes)},
          },
          'source': ['![$name](attachment:$name)'],
        });
      } else if (text.trim().isNotEmpty) {
        cells.add({'cell_type': 'markdown', 'metadata': {}, 'source': _lines(text)});
      }
    }
    final isPython = lang == Language.python;
    return const JsonEncoder.withIndent(' ').convert({
      'cells': cells,
      'metadata': {
        'kernelspec': isPython
            ? {'display_name': 'Python 3', 'language': 'python', 'name': 'python3'}
            : {'display_name': lang.name, 'language': lang.name, 'name': lang.name},
        'language_info': {'name': isPython ? 'python' : lang.name},
      },
      'nbformat': 4,
      'nbformat_minor': 5,
    });
  }
}

/// Files as notes and back, for workspaces.
class FileNotes {
  FileNotes._();

  static const _uuid = Uuid();

  /// Blocks for a file's text. `.py` files split into cells at `# %%`
  /// lines (like VS Code and Spyder); `# %% [markdown]` cells become
  /// Markdown blocks. `.md` is one Markdown block.
  static List<BlockEntity> blocksFor(String fileName, String text) {
    final ext = p.extension(fileName).toLowerCase();
    if (ext == '.md' || ext == '.markdown') return [MarkdownBlockEntity(id: _uuid.v4(), text: text)];
    final language = languageForFileName(fileName);
    if (ext == '.py' && RegExp(r'^# ?%%', multiLine: true).hasMatch(text)) {
      final blocks = <BlockEntity>[];
      final buf = <String>[];
      var markdown = false;
      void flush() {
        final body = buf.join('\n').trim();
        buf.clear();
        if (body.isEmpty) return;
        if (markdown) {
          final md = body.split('\n').map((l) => l.startsWith('# ') ? l.substring(2) : (l == '#' ? '' : l)).join('\n');
          blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: md));
        } else {
          blocks.add(CodeBlockEntity(id: _uuid.v4(), text: body, language: language));
        }
      }

      for (final line in text.split('\n')) {
        if (RegExp(r'^# ?%%').hasMatch(line)) {
          flush();
          markdown = line.contains('[markdown]');
          continue;
        }
        buf.add(line);
      }
      flush();
      return blocks;
    }
    return [CodeBlockEntity(id: _uuid.v4(), text: text, language: language == Language.none ? Language.markdown : language)];
  }

  /// The file text for a note (the reverse of [blocksFor]).
  static String textFor(String fileName, NoteEntity note) {
    final ext = p.extension(fileName).toLowerCase();
    if (ext == '.ipynb') {
      return IpynbExport.fromNote(note, readImage: (path) {
        try {
          return File(path).readAsBytesSync();
        } catch (_) {
          return null;
        }
      });
    }
    if (ext == '.md' || ext == '.markdown') {
      return note.blocks.map((b) {
        if (b is CodeBlockEntity) return '```${b.language.name}\n${b.text ?? ''}\n```';
        if (b is ImageBlockEntity) return '![](${b.imagePath})';
        return b.text ?? '';
      }).join('\n\n');
    }
    final code = note.blocks.where((b) => b is CodeBlockEntity || b is MarkdownBlockEntity || b is NoteBlockEntity).toList();
    final cells = code.length > 1 || code.any((b) => b is! CodeBlockEntity);
    if (ext == '.py' && cells) {
      return code.map((b) {
        if (b is CodeBlockEntity) return '# %%\n${(b.text ?? '').trimRight()}';
        final md = (b.text ?? '').split('\n').map((l) => l.isEmpty ? '#' : '# $l').join('\n');
        return '# %% [markdown]\n$md';
      }).join('\n\n');
    }
    return note.blocks.whereType<CodeBlockEntity>().map((b) => b.text ?? '').join('\n\n');
  }
}
