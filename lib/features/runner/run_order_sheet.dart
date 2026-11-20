import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../constants/themes.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import '../notes/domain/entities/run_plan.dart';
import '../notes/presentation/bloc/note_group_bloc.dart';
import '../notes/presentation/bloc/note_group_event.dart';
import 'run_manager.dart';

/// Sets the order ▶ Run folder uses: drag notes into order, turn them on or
/// off, choose "wait until it finishes" or "keep running", and pick the
/// ★ primary note, which always runs last and keeps running.
Future<void> showRunOrderSheet(BuildContext context, NoteGroupEntity group, List<NoteEntity> notes) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider.value(
      value: context.read<NoteGroupBloc>(),
      child: _RunOrderSheet(group: group, notes: notes),
    ),
  );
}

class _RunOrderSheet extends StatefulWidget {
  const _RunOrderSheet({required this.group, required this.notes});
  final NoteGroupEntity group;
  final List<NoteEntity> notes;

  @override
  State<_RunOrderSheet> createState() => _RunOrderSheetState();
}

class _RunOrderSheetState extends State<_RunOrderSheet> {
  late final Map<String, NoteEntity> _byId;
  late List<String> _order;
  String? _primary;
  late Set<String> _keep;
  late Set<String> _off;

  @override
  void initState() {
    super.initState();
    final runnable = RunManager.runnableNotes(widget.group, widget.notes);
    _byId = {for (final n in runnable) n.id: n};
    final plan = widget.group.runPlan ?? const RunPlan();
    final ids = runnable.map((n) => n.id).toList();
    _order = plan.orderFor(ids);
    _primary = plan.primaryFor(ids);
    _keep = {...plan.keepRunning};
    _off = {...plan.disabled};
    _primaryLast();
  }

  /// The primary note always sits at the end.
  void _primaryLast() {
    final p = _primary;
    if (p == null || !_order.contains(p)) return;
    _order
      ..remove(p)
      ..add(p);
  }

  void _save() {
    final plan = RunPlan(order: _order, primary: _primary, keepRunning: _keep, disabled: _off);
    context.read<NoteGroupBloc>().add(UpdateGroupEvent(widget.group.copyWith(runPlan: plan, lastModified: DateTime.now())));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(children: [
                Expanded(child: Text('Run order', style: Theme.of(context).textTheme.titleMedium)),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '▶ Run folder starts these notes one after another, top to bottom. Each one finishes before the next '
                'starts, unless you set it to keep running. The ★ primary note always goes last and keeps running. '
                'Web pages in the folder open at the end.',
                style: TextStyle(color: tokens.subtle, fontSize: 13.5),
              ),
            ),
            Expanded(
              child: _order.isEmpty
                  ? Center(child: Text('No notes with Python, Bash, JavaScript or Dart code here yet.',
                      style: TextStyle(color: tokens.subtle)))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      buildDefaultDragHandles: false,
                      itemCount: _order.length,
                      onReorder: (from, to) => setState(() {
                        if (to > from) to--;
                        final id = _order.removeAt(from);
                        _order.insert(to, id);
                        _primaryLast();
                      }),
                      itemBuilder: (context, i) {
                        final id = _order[i];
                        final note = _byId[id]!;
                        final on = !_off.contains(id);
                        final primary = id == _primary;
                        final steps = _order.where((x) => !_off.contains(x)).toList();
                        final number = on ? '${steps.indexOf(id) + 1}' : '–';
                        return Card(
                          key: ValueKey(id),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                            child: Row(children: [
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_indicator_rounded),
                                ),
                              ),
                              SizedBox(
                                width: 26,
                                child: Text(number, style: monoStyle(context, size: 14, color: on ? color.primary : tokens.subtle)),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(note.title.isEmpty ? 'Untitled' : note.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: on ? null : tokens.subtle,
                                          decoration: on ? null : TextDecoration.lineThrough)),
                                  const SizedBox(height: 4),
                                  if (primary)
                                    Text('★ primary · runs last and keeps running',
                                        style: monoStyle(context, size: 12, color: tokens.pin))
                                  else if (on)
                                    Wrap(spacing: 6, children: [
                                      ChoiceChip(
                                        label: const Text('wait until it finishes'),
                                        visualDensity: VisualDensity.compact,
                                        selected: !_keep.contains(id),
                                        onSelected: (_) => setState(() => _keep.remove(id)),
                                      ),
                                      ChoiceChip(
                                        label: const Text('keep running'),
                                        visualDensity: VisualDensity.compact,
                                        selected: _keep.contains(id),
                                        onSelected: (_) => setState(() => _keep.add(id)),
                                      ),
                                    ]),
                                ]),
                              ),
                              IconButton(
                                tooltip: primary ? 'Primary note' : 'Make this the primary note',
                                icon: Icon(primary ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: primary ? tokens.pin : null),
                                onPressed: !on
                                    ? null
                                    : () => setState(() {
                                          _primary = id;
                                          _keep.remove(id);
                                          _primaryLast();
                                        }),
                              ),
                              Switch(
                                value: on,
                                onChanged: (v) => setState(() {
                                  if (v) {
                                    _off.remove(id);
                                  } else {
                                    _off.add(id);
                                    if (primary) {
                                      final rest = _order.where((x) => !_off.contains(x)).toList();
                                      _primary = rest.isEmpty ? null : rest.last;
                                      _primaryLast();
                                    }
                                  }
                                }),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
