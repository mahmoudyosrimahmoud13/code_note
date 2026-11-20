import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../constants/themes.dart';
import '../notes/presentation/pages/web_preview_page.dart';
import 'pyodide/pyodide_runtime.dart';
import 'run_manager.dart';
import 'sandbox_files_sheet.dart';

/// A table made by pandas (or polars) in a Python block.
class OutputTable {
  OutputTable(this.columns, this.index, this.rows, this.shape, this.truncated);
  final List<String> columns;
  final List<String> index;
  final List<List<Object?>> rows;
  final String shape;
  final bool truncated;

  static OutputTable? read(String path) {
    try {
      final m = json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;
      return OutputTable(
        [for (final c in m['columns'] as List) '$c'],
        [for (final i in m['index'] as List) '$i'],
        [for (final r in m['data'] as List) List<Object?>.from(r as List)],
        '${m['shape'] ?? ''}',
        m['truncated'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  static String cell(Object? v) {
    if (v == null) return 'NaN';
    if (v is double) return v == v.roundToDouble() && v.abs() < 1e15 ? v.toStringAsFixed(1) : _short(v);
    return '$v';
  }

  static String _short(double v) {
    final s = v.toStringAsFixed(6);
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }

  /// A Markdown table, for saving output into the note.
  String toMarkdown({int maxRows = 50}) {
    String esc(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');
    final b = StringBuffer()
      ..writeln('| | ${columns.map(esc).join(' | ')} |')
      ..writeln('|---|${List.filled(columns.length, '---:').join('|')}|');
    for (var i = 0; i < rows.length && i < maxRows; i++) {
      b.writeln('| **${esc(index[i])}** | ${rows[i].map((v) => esc(cell(v))).join(' | ')} |');
    }
    b.write('\n*$shape${rows.length > maxRows || truncated ? ', first ${rows.length < maxRows ? rows.length : maxRows} shown' : ''}*');
    return b.toString();
  }
}

/// Draws one rich output: an image, a table, Markdown or an HTML button.
class RichOutputView extends StatelessWidget {
  const RichOutputView(this.output, {super.key});
  final RichOutput output;

  @override
  Widget build(BuildContext context) {
    return switch (output.kind) {
      'image' => _ImageOutput(path: output.path),
      'table' => _TableOutput(path: output.path),
      'markdown' => _MarkdownOutput(path: output.path),
      'missing' => MissingPackagesCard(names: output.path.split(',').where((n) => n.isNotEmpty).toList()),
      _ => _HtmlOutput(output: output),
    };
  }
}

class _ImageOutput extends StatelessWidget {
  const _ImageOutput({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(children: [
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (c) => Dialog(
                backgroundColor: Colors.white,
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(maxScale: 6, child: Image.file(file)),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(file, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('(image is gone)')),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton.filledTonal(
              tooltip: 'Save a copy',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.save_alt_rounded),
              onPressed: () => saveCopyOf(file),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TableOutput extends StatefulWidget {
  const _TableOutput({required this.path});
  final String path;

  @override
  State<_TableOutput> createState() => _TableOutputState();
}

class _TableOutputState extends State<_TableOutput> {
  late final OutputTable? _table = OutputTable.read(widget.path);
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = _table;
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (t == null) return const Text('(table is gone)');
    final shown = _all ? t.rows.length : (t.rows.length < 30 ? t.rows.length : 30);
    TextStyle mono({FontWeight? weight, Color? c}) => monoStyle(context, size: 12, weight: weight ?? FontWeight.w400, color: c);
    Widget cell(String text, {bool head = false, bool index = false, bool right = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(text,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: mono(weight: head || index ? FontWeight.w700 : null, c: head ? color.primary : null)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: color.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(horizontalInside: BorderSide(color: color.outlineVariant.withAlpha(120))),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: color.surfaceContainerHigh),
                  children: [cell('', head: true), for (final c in t.columns) cell(c, head: true, right: true)],
                ),
                for (var i = 0; i < shown; i++)
                  TableRow(
                    decoration: BoxDecoration(color: i.isOdd ? color.surfaceContainerLow : null),
                    children: [
                      cell(t.index[i], index: true),
                      for (final v in t.rows[i]) cell(OutputTable.cell(v), right: v is num),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Row(children: [
          Text('${t.shape}${t.truncated ? ' (first ${t.rows.length} kept)' : ''}',
              style: monoStyle(context, size: 11.5, color: tokens.subtle)),
          if (t.rows.length > 30)
            TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? 'show fewer' : 'show all ${t.rows.length} rows'),
            ),
        ]),
      ]),
    );
  }
}

class _MarkdownOutput extends StatelessWidget {
  const _MarkdownOutput({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    String text;
    try {
      text = File(path).readAsStringSync();
    } catch (_) {
      text = '(output is gone)';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: MarkdownBody(data: text, selectable: true),
    );
  }
}

class _HtmlOutput extends StatelessWidget {
  const _HtmlOutput({required this.output});
  final RichOutput output;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton.icon(
        onPressed: () => WebPreview.openFile(context, output.path, title: output.note),
        icon: const Icon(Icons.open_in_new_rounded, size: 18),
        label: Text('Open interactive output${output.note.isEmpty ? '' : ' (${output.note})'}'),
      ),
    );
  }
}


/// Under a block on a phone: Python or a package isn't downloaded yet.
/// One tap downloads it (with a progress bar), then ▶ runs the block again.
/// "@python" means Python itself.
class MissingPackagesCard extends StatefulWidget {
  const MissingPackagesCard({super.key, required this.names});
  final List<String> names;

  @override
  State<MissingPackagesCard> createState() => _MissingPackagesCardState();
}

class _MissingPackagesCardState extends State<MissingPackagesCard> {
  double? _progress;
  String? _status;
  bool _done = false;
  String? _error;

  bool get _python => widget.names.contains('@python');
  List<String> get _packages => widget.names.where((n) => n != '@python').toList();

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    final rt = PyodideRuntime.instance;
    void report(double x, String s) {
      if (!mounted) return;
      setState(() {
        _progress = x;
        _status = s;
      });
    }

    try {
      if (_python) await rt.downloadCore(onProgress: report);
      if (_packages.isNotEmpty) {
        final notFound = await rt.downloadPackages(_packages, onProgress: report);
        if (notFound.isNotEmpty) {
          _error = "Couldn't find ${notFound.join(', ')} for phones. Packages need a pure-Python or Pyodide build.";
        }
      }
      _done = _error == null;
    } catch (e) {
      _error = '$e'.replaceFirst('RuntimeException: ', '');
    }
    if (mounted) setState(() => _progress = null);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final what = [if (_python) 'Python', ..._packages].join(', ');
    final title = _done
        ? 'Downloaded. Press ▶ to run the block again.'
        : _python
            ? "Python isn't on this phone yet"
            : '${_packages.length == 1 ? 'This block needs' : 'This block needs these packages'}: ${_packages.join(', ')}';
    final body = _done
        ? 'It stays on this phone, so it works offline from now on.'
        : _python
            ? 'Download it once (about 12 MB). It goes into CodeNote\'s sandbox and works offline afterwards.'
            : 'Download ${_packages.length == 1 ? 'it' : 'them'} once into CodeNote\'s sandbox. '
                'Manage downloads in Settings > Runtimes and sandbox.';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.primaryContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.primary.withAlpha(90)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_done ? Icons.check_circle_rounded : Icons.download_rounded, color: color.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        Text(body, style: TextStyle(color: color.onSurfaceVariant, fontSize: 13.5)),
        if (_progress != null) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          if (_status != null) ...[
            const SizedBox(height: 4),
            Text(_status!, style: TextStyle(color: color.onSurfaceVariant, fontSize: 12.5)),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: color.error, fontSize: 13)),
        ],
        if (!_done && _progress == null) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Download $what'),
          ),
        ],
      ]),
    );
  }
}
