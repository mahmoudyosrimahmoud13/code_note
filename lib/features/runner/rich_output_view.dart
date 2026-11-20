import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../constants/themes.dart';
import '../notes/presentation/pages/web_preview_page.dart';
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
