import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A table read from a CSV, TSV or JSON file, for the data viewer.
class DataTableData {
  DataTableData(this.columns, this.rows, {this.truncated = false});
  final List<String> columns;
  final List<List<String>> rows;

  /// The file had more rows than the viewer reads.
  final bool truncated;

  static const maxRows = 100000;
  static const maxBytes = 60 * 1024 * 1024;

  /// Reads [path] in the background, so big files don't freeze the app.
  static Future<DataTableData> load(String path) => compute(_load, path);

  static DataTableData _load(String path) {
    final file = File(path);
    final size = file.lengthSync();
    final ext = p.extension(path).toLowerCase();
    String text;
    var cut = false;
    if (size > maxBytes) {
      final raf = file.openSync();
      final bytes = raf.readSync(maxBytes);
      raf.closeSync();
      text = utf8.decode(bytes, allowMalformed: true);
      text = text.substring(0, text.lastIndexOf('\n') + 1);
      cut = true;
    } else {
      text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    }
    if (text.startsWith('﻿')) text = text.substring(1);
    final data = switch (ext) {
      '.json' => parseJson(text),
      '.jsonl' => parseJsonLines(text),
      '.tsv' => parseDelimited(text, delimiter: '\t'),
      _ => parseDelimited(text),
    };
    return cut ? DataTableData(data.columns, data.rows, truncated: true) : data;
  }

  /// CSV (or any delimited text) with quotes, as in RFC 4180. The
  /// delimiter is guessed from the first line when not given.
  static DataTableData parseDelimited(String text, {String? delimiter}) {
    final firstLine = text.split('\n').first;
    final d = delimiter ?? _guessDelimiter(firstLine);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    var truncated = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
        continue;
      }
      if (c == '"' && cell.isEmpty) {
        quoted = true;
      } else if (c == d) {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
        row = <String>[];
        if (rows.length > maxRows) {
          truncated = true;
          break;
        }
      } else {
        cell.write(c);
      }
    }
    if (!truncated && (cell.isNotEmpty || row.isNotEmpty)) {
      row.add(cell.toString());
      rows.add(row);
    }
    if (rows.isEmpty) return DataTableData(const [], const []);
    final header = rows.first;
    final width = rows.fold<int>(header.length, (m, r) => r.length > m ? r.length : m);
    final columns = [
      for (var i = 0; i < width; i++) i < header.length && header[i].trim().isNotEmpty ? header[i].trim() : 'column ${i + 1}'
    ];
    final body = [
      for (final r in rows.skip(1).take(maxRows)) [for (var i = 0; i < width; i++) i < r.length ? r[i] : '']
    ];
    return DataTableData(columns, body, truncated: truncated);
  }

  static String _guessDelimiter(String line) {
    var best = ',', count = 0;
    for (final d in const [',', ';', '\t', '|']) {
      final n = d.allMatches(line).length;
      if (n > count) {
        best = d;
        count = n;
      }
    }
    return best;
  }

  /// A list of objects ([{...}, {...}]), an object of lists
  /// ({"a": [..], "b": [..]}), or an object holding one of those.
  static DataTableData parseJson(String text) {
    final Object? data = json.decode(text);
    return _fromJson(data);
  }

  static DataTableData parseJsonLines(String text) {
    final items = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) json.decode(line)
    ];
    return _fromJson(items);
  }

  static DataTableData _fromJson(Object? data) {
    if (data is Map) {
      final lists = data.values.whereType<List>().toList();
      if (lists.length == data.length && lists.isNotEmpty) {
        final columns = [for (final k in data.keys) '$k'];
        final n = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
        return DataTableData(columns, [
          for (var i = 0; i < n && i < maxRows; i++) [for (final l in lists) i < l.length ? _cell(l[i]) : '']
        ], truncated: n > maxRows);
      }
      // {"data": [...]} and similar.
      final inner = data.values.whereType<List>().where((l) => l.isNotEmpty && l.first is Map).toList();
      if (inner.isNotEmpty) return _fromJson(inner.first);
      return DataTableData(const ['key', 'value'], [
        for (final e in data.entries) [_cell(e.key), _cell(e.value)]
      ]);
    }
    if (data is List) {
      final maps = data.whereType<Map>().toList();
      if (maps.isEmpty) return DataTableData(const ['value'], [for (final v in data.take(maxRows)) [_cell(v)]]);
      final columns = <String>[];
      for (final m in maps.take(2000)) {
        for (final k in m.keys) {
          if (!columns.contains('$k')) columns.add('$k');
        }
      }
      return DataTableData(columns, [
        for (final m in maps.take(maxRows)) [for (final c in columns) _cell(m[c])]
      ], truncated: maps.length > maxRows);
    }
    return DataTableData(const ['value'], [[_cell(data)]]);
  }

  static String _cell(Object? v) => v == null ? '' : (v is String ? v : json.encode(v));
}

/// What a column holds, for the stats sheet and charts.
class ColumnStats {
  ColumnStats({
    required this.name,
    required this.count,
    required this.missing,
    required this.unique,
    required this.numeric,
    this.min,
    this.max,
    this.mean,
    this.median,
    this.histogram = const [],
    this.histogramEdges = const [],
    this.top = const [],
  });

  final String name;
  final int count;
  final int missing;
  final int unique;
  final bool numeric;
  final double? min, max, mean, median;

  /// Counts per bin (numbers).
  final List<int> histogram;
  final List<double> histogramEdges;

  /// Most common values (text), with counts.
  final List<(String, int)> top;

  static bool isMissing(String v) {
    final t = v.trim().toLowerCase();
    return t.isEmpty || t == 'na' || t == 'nan' || t == 'null' || t == 'none' || t == 'n/a';
  }

  static double? number(String v) => double.tryParse(v.trim().replaceAll(',', ''));

  static ColumnStats of(DataTableData data, int column) {
    final values = [for (final r in data.rows) r[column]];
    final present = values.where((v) => !isMissing(v)).toList();
    final nums = [for (final v in present) number(v)].whereType<double>().toList();
    final numeric = present.isNotEmpty && nums.length >= present.length * 0.9;
    final counts = <String, int>{};
    for (final v in present) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (!numeric || nums.isEmpty) {
      return ColumnStats(
        name: data.columns[column],
        count: values.length,
        missing: values.length - present.length,
        unique: counts.length,
        numeric: false,
        top: [for (final e in top.take(8)) (e.key, e.value)],
      );
    }
    nums.sort();
    final mn = nums.first, mx = nums.last;
    final mean = nums.reduce((a, b) => a + b) / nums.length;
    final median = nums.length.isOdd ? nums[nums.length ~/ 2] : (nums[nums.length ~/ 2 - 1] + nums[nums.length ~/ 2]) / 2;
    const bins = 12;
    final hist = List.filled(bins, 0);
    final span = mx - mn;
    for (final v in nums) {
      final i = span == 0 ? 0 : ((v - mn) / span * bins).floor().clamp(0, bins - 1);
      hist[i]++;
    }
    return ColumnStats(
      name: data.columns[column],
      count: values.length,
      missing: values.length - present.length,
      unique: counts.length,
      numeric: true,
      min: mn,
      max: mx,
      mean: mean,
      median: median,
      histogram: hist,
      histogramEdges: [for (var i = 0; i <= bins; i++) mn + span * i / bins],
      top: [for (final e in top.take(5)) (e.key, e.value)],
    );
  }

  static Future<List<ColumnStats>> all(DataTableData data) => compute(_all, data);

  static List<ColumnStats> _all(DataTableData d) => [for (var i = 0; i < d.columns.length; i++) of(d, i)];
}

/// Sorting and filtering for the viewer, in the background for big tables.
class DataQuery {
  const DataQuery(this.data, {this.filter = '', this.sortColumn, this.descending = false});
  final DataTableData data;
  final String filter;
  final int? sortColumn;
  final bool descending;

  /// Row numbers to show, in order.
  static Future<List<int>> run(DataQuery q) =>
      q.data.rows.length < 5000 ? Future.value(_run(q)) : compute(_run, q);

  static List<int> _run(DataQuery q) {
    final f = q.filter.trim().toLowerCase();
    final rows = q.data.rows;
    var order = <int>[
      for (var i = 0; i < rows.length; i++)
        if (f.isEmpty || rows[i].any((c) => c.toLowerCase().contains(f))) i
    ];
    final c = q.sortColumn;
    if (c != null) {
      final nums = rows.where((r) => !ColumnStats.isMissing(r[c])).take(200).every((r) => ColumnStats.number(r[c]) != null);
      int cmp(int a, int b) {
        final x = rows[a][c], y = rows[b][c];
        final mx = ColumnStats.isMissing(x), my = ColumnStats.isMissing(y);
        if (mx || my) return mx == my ? 0 : (mx ? 1 : -1); // missing last
        final r = nums
            ? (ColumnStats.number(x) ?? 0).compareTo(ColumnStats.number(y) ?? 0)
            : x.toLowerCase().compareTo(y.toLowerCase());
        return q.descending ? -r : r;
      }

      order.sort(cmp);
    }
    return order;
  }
}
