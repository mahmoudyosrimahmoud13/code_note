import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../constants/themes.dart';
import 'data_table.dart';
import 'workspace_actions.dart';
import 'workspace_service.dart';

/// Look at a data file without writing code: a table you can sort and
/// search, what each column holds, and a chart per column. "Analyze in a
/// notebook" writes the pandas code for you.
class DataViewerPage extends StatelessWidget {
  const DataViewerPage({super.key, required this.path, this.workspace});
  final String path;
  final WorkspaceInfo? workspace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p.basename(path), style: monoStyle(context, size: 16, weight: FontWeight.w700))),
      body: DataView(path: path, workspace: workspace),
    );
  }
}

class DataView extends StatefulWidget {
  const DataView({super.key, required this.path, this.workspace});
  final String path;
  final WorkspaceInfo? workspace;

  @override
  State<DataView> createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  DataTableData? _data;
  String? _error;
  List<int> _order = const [];
  int? _sort;
  bool _desc = false;
  String _filter = '';
  List<double> _widths = const [];
  final _hScroll = ScrollController();
  int _query = 0;

  bool get _needsPython {
    final ext = p.extension(widget.path).toLowerCase();
    return ext == '.xlsx' || ext == '.xls' || ext == '.parquet';
  }

  @override
  void initState() {
    super.initState();
    if (!_needsPython) _load();
  }

  @override
  void didUpdateWidget(DataView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      setState(() {
        _data = null;
        _error = null;
        _sort = null;
        _filter = '';
      });
      if (!_needsPython) _load();
    }
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await DataTableData.load(widget.path);
      if (!mounted) return;
      setState(() {
        _data = data;
        _order = List.generate(data.rows.length, (i) => i);
        _widths = _columnWidths(data);
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't read this file as a table: $e");
    }
  }

  List<double> _columnWidths(DataTableData d) {
    return [
      for (var c = 0; c < d.columns.length; c++)
        (() {
          var longest = d.columns[c].length + 2;
          for (final r in d.rows.take(200)) {
            longest = math.max(longest, r[c].length);
          }
          return (longest * 8.0 + 24).clamp(70.0, 260.0).toDouble();
        })()
    ];
  }

  Future<void> _requery() async {
    final data = _data;
    if (data == null) return;
    final ticket = ++_query;
    final order = await DataQuery.run(DataQuery(data, filter: _filter, sortColumn: _sort, descending: _desc));
    if (mounted && ticket == _query) setState(() => _order = order);
  }

  void _tapHeader(int c) {
    setState(() {
      if (_sort == c) {
        if (_desc) {
          _sort = null;
          _desc = false;
        } else {
          _desc = true;
        }
      } else {
        _sort = c;
        _desc = false;
      }
    });
    _requery();
  }

  Future<void> _showColumn(int c) async {
    final data = _data;
    if (data == null) return;
    final stats = ColumnStats.of(data, c);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ColumnSheet(stats: stats),
    );
  }

  Future<void> _showSummary() async {
    final data = _data;
    if (data == null) return;
    final stats = await ColumnStats.all(data);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text('Summary', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('${data.rows.length} rows · ${data.columns.length} columns. Tap a column for its chart.',
              style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (var i = 0; i < stats.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(stats[i].numeric ? Icons.tag_rounded : Icons.text_fields_rounded),
              title: Text(stats[i].name),
              subtitle: Text(_oneLine(stats[i])),
              onTap: () {
                Navigator.pop(c);
                _showColumn(i);
              },
            ),
        ]),
      ),
    );
  }

  static String _num(double? v) {
    if (v == null) return '–';
    if (v == v.roundToDouble() && v.abs() < 1e12) return v.toStringAsFixed(0);
    final s = v.abs() >= 100 ? v.toStringAsFixed(1) : v.toStringAsFixed(3);
    // 17.100 -> 17.1
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _oneLine(ColumnStats s) {
    final missing = s.missing == 0 ? 'nothing missing' : '${s.missing} missing';
    if (s.numeric) return 'numbers · ${_num(s.min)} to ${_num(s.max)} · mean ${_num(s.mean)} · $missing';
    return 'text · ${s.unique} different values · $missing';
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (_needsPython) {
      return _Empty(
        icon: Icons.grid_on_rounded,
        title: '${p.extension(widget.path).substring(1).toUpperCase()} files open with Python',
        body: 'Excel and Parquet need pandas to read. Make a notebook that loads this file and shows its first rows, '
            'a summary and charts.',
        action: FilledButton.icon(
          onPressed: () => WorkspaceActions.analyzeInNotebook(context, widget.path, workspace: widget.workspace),
          icon: const Icon(Icons.auto_graph_rounded),
          label: const Text('Analyze in a notebook'),
        ),
      );
    }
    if (_error != null) return _Empty(icon: Icons.error_outline_rounded, title: "Can't show this file", body: _error!);
    final data = _data;
    if (data == null) return const Center(child: CircularProgressIndicator());
    if (data.columns.isEmpty) return const _Empty(icon: Icons.inbox_outlined, title: 'This file is empty', body: '');

    final totalWidth = 56 + _widths.fold<double>(0, (a, b) => a + b);
    final mono = monoStyle(context, size: 12.5);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                hintText: 'Search all columns',
              ),
              onChanged: (v) {
                _filter = v;
                _requery();
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Summary of every column',
            onPressed: _showSummary,
            icon: const Icon(Icons.insights_rounded),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => WorkspaceActions.analyzeInNotebook(context, widget.path, workspace: widget.workspace),
            icon: const Icon(Icons.auto_graph_rounded, size: 18),
            label: const Text('Analyze'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Row(children: [
          Expanded(
            child: Text(
              '${_order.length == data.rows.length ? '' : '${_order.length} of '}${data.rows.length} rows'
              '${data.truncated ? ' (first part of a big file)' : ''} · ${data.columns.length} columns'
              ' · tap a column name to sort, hold it for details',
              style: TextStyle(color: tokens.subtle, fontSize: 12.5),
              maxLines: 2,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(children: [
                Container(
                  color: color.surfaceContainerHigh,
                  child: Row(children: [
                    const SizedBox(width: 56),
                    for (var c = 0; c < data.columns.length; c++)
                      InkWell(
                        onTap: () => _tapHeader(c),
                        onLongPress: () => _showColumn(c),
                        child: Container(
                          width: _widths[c],
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: Row(children: [
                            Expanded(
                              child: Text(data.columns[c],
                                  overflow: TextOverflow.ellipsis,
                                  style: monoStyle(context, size: 12.5, weight: FontWeight.w700)),
                            ),
                            if (_sort == c)
                              Icon(_desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 14),
                          ]),
                        ),
                      ),
                  ]),
                ),
                Expanded(
                  // Only the rows on screen are built, so 100,000 rows scroll smoothly.
                  child: ListView.builder(
                    itemCount: _order.length,
                    itemExtent: 34,
                    itemBuilder: (context, i) {
                      final r = data.rows[_order[i]];
                      return Container(
                        color: i.isOdd ? color.surfaceContainerLowest : null,
                        child: Row(children: [
                          SizedBox(
                            width: 56,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text('${_order[i] + 1}', style: monoStyle(context, size: 11, color: tokens.subtle)),
                            ),
                          ),
                          for (var c = 0; c < r.length; c++)
                            SizedBox(
                              width: _widths[c],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  ColumnStats.isMissing(r[c]) ? '–' : r[c].replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ColumnStats.isMissing(r[c]) ? mono.copyWith(color: tokens.subtle) : mono,
                                ),
                              ),
                            ),
                        ]),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _ColumnSheet extends StatelessWidget {
  const _ColumnSheet({required this.stats});
  final ColumnStats stats;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final s = stats;
    String n(double? v) => _DataViewState._num(v);
    final facts = <(String, String)>[
      ('Values', '${s.count}'),
      ('Missing', s.missing == 0 ? 'none' : '${s.missing} (${(s.missing * 100 / math.max(1, s.count)).toStringAsFixed(1)}%)'),
      ('Different values', '${s.unique}'),
      if (s.numeric) ...[
        ('Smallest', n(s.min)),
        ('Largest', n(s.max)),
        ('Average', n(s.mean)),
        ('Middle (median)', n(s.median)),
      ],
    ];
    final bars = s.numeric ? s.histogram : [for (final t in s.top) t.$2];
    final labels = s.numeric
        ? [for (var i = 0; i < s.histogram.length; i++) n(s.histogramEdges[i])]
        : [for (final t in s.top) t.$1];
    final most = bars.isEmpty ? 1 : bars.reduce(math.max);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.name, style: Theme.of(context).textTheme.titleLarge),
          Text(s.numeric ? 'Numbers' : 'Text', style: TextStyle(color: color.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 8, children: [
            for (final (k, v) in facts)
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(k, style: TextStyle(color: color.onSurfaceVariant, fontSize: 12)),
                Text(v, style: monoStyle(context, size: 14, weight: FontWeight.w700)),
              ]),
          ]),
          if (bars.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(s.numeric ? 'How the values spread' : 'Most common values',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            if (s.numeric)
              SizedBox(
                height: 120,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < bars.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: '${labels[i]}…: ${bars[i]}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: math.max(2, 120 * bars[i] / most),
                          decoration: BoxDecoration(
                            color: color.primary,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                ]),
              )
            else
              for (var i = 0; i < bars.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(labels[i], maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (c, box) => Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            height: 16,
                            width: math.max(2, box.maxWidth * bars[i] / most),
                            decoration: BoxDecoration(color: color.primary, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${bars[i]}', style: monoStyle(context, size: 12)),
                  ]),
                ),
            if (s.numeric)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Text(n(s.min), style: monoStyle(context, size: 11)),
                  const Spacer(),
                  Text(n(s.max), style: monoStyle(context, size: 11)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}
