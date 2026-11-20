import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/themes.dart';

/// One thing the palette can do: an action, a note or a folder.
class PaletteItem {
  const PaletteItem({
    required this.label,
    required this.icon,
    required this.run,
    this.hint,
    this.keywords = '',
    this.group = 'Actions',
  });

  final String label;
  final IconData icon;
  final VoidCallback run;

  /// Shown on the right, like a shortcut ("Ctrl+N") or a folder name.
  final String? hint;

  /// Extra words that should find this item.
  final String keywords;

  /// Section title: "Actions", "Notes" or "Folders".
  final String group;
}

/// Opens the command palette (Ctrl+K). Type to filter, arrows to move,
/// Enter to run, Esc to close.
Future<void> showCommandPalette(BuildContext context, List<PaletteItem> items) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _CommandPalette(items: items),
  );
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.items});
  final List<PaletteItem> items;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  String _query = '';
  int _selected = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Simple fuzzy match: every typed word must appear somewhere.
  List<PaletteItem> get _results {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final matches = widget.items.where((item) {
      final hay = '${item.label} ${item.keywords} ${item.hint ?? ''}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();
    // With no query, show actions first and only a few notes.
    if (words.isEmpty) {
      final actions = matches.where((i) => i.group == 'Actions').toList();
      final rest = matches.where((i) => i.group != 'Actions').take(6);
      return [...actions, ...rest];
    }
    return matches.take(40).toList();
  }

  bool _ran = false;

  void _run(PaletteItem item) {
    if (_ran) return; // never pop twice
    _ran = true;
    Navigator.pop(context);
    // Run after the palette closes, so pages open on top of the home screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => item.run());
  }

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + by) % count);
    final offset = (_selected * 44.0) - 120;
    if (_scroll.hasClients) {
      _scroll.animateTo(
        offset.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final results = _results;
    if (_selected >= results.length) _selected = 0;

    String? lastGroup;
    final rows = <Widget>[];
    for (var i = 0; i < results.length; i++) {
      final item = results[i];
      if (item.group != lastGroup) {
        lastGroup = item.group;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text('// ${item.group.toLowerCase()}',
              style: monoStyle(context, size: 11, color: tokens.subtle)),
        ));
      }
      final selected = i == _selected;
      rows.add(Material(
        color: selected ? color.primary.withAlpha(40) : Colors.transparent,
        child: InkWell(
          onTap: () => _run(item),
          onHover: (h) {
            if (h) setState(() => _selected = i);
          },
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(item.icon,
                    size: 18, color: selected ? color.primary : color.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                ),
                if (item.hint != null)
                  Text(item.hint!, style: monoStyle(context, size: 11, color: tokens.subtle)),
              ]),
            ),
          ),
        ),
      ));
    }

    return Align(
      alignment: const Alignment(0, -0.55),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 460),
        child: Material(
          color: color.surfaceContainer,
          elevation: 12,
          borderRadius: BorderRadius.circular(AppBrand.radius),
          clipBehavior: Clip.antiAlias,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1, results.length),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1, results.length),
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    autofocus: true,
                    style: monoStyle(context, size: 15),
                    decoration: InputDecoration(
                      hintText: 'Type a command or search notes…',
                      hintStyle: monoStyle(context, size: 15, color: tokens.subtle),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 6),
                        child: Text('>',
                            style: monoStyle(context,
                                size: 18, weight: FontWeight.w700, color: tokens.success)),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 0),
                    ),
                    onChanged: (q) => setState(() {
                      _query = q;
                      _selected = 0;
                    }),
                    onSubmitted: (_) {
                      if (results.isNotEmpty) _run(results[_selected]);
                    },
                  ),
                ),
                Divider(height: 1, color: color.outlineVariant),
                Flexible(
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('no matches',
                              style: monoStyle(context, color: tokens.subtle)),
                        )
                      : ListView(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 8),
                          children: rows,
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: color.surfaceContainerHigh,
                  child: Row(children: [
                    Text('↑↓ move   ⏎ open   esc close',
                        style: monoStyle(context, size: 11, color: tokens.subtle)),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
