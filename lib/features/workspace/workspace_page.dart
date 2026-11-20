import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:path/path.dart' as p;

import '../../constants/themes.dart';
import '../../core/util/code_languages.dart';
import '../../core/util/platform_helper.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/presentation/bloc/note_bloc.dart';
import '../notes/presentation/bloc/note_state.dart';
import '../notes/presentation/bloc/note_group_bloc.dart';
import '../notes/presentation/bloc/note_group_state.dart';
import '../notes/presentation/pages/note_page.dart';
import '../runner/code_runner.dart';
import '../runner/pyodide/pyodide_runtime.dart';
import '../runner/run_manager.dart';
import '../runner/run_panel.dart';
import '../runner/sandbox_files_sheet.dart';
import '../runner/terminal_page.dart';
import 'data_viewer_page.dart';
import 'workspace_actions.dart';
import 'workspace_service.dart';

/// A folder opened like a small IDE: the files on one side, the open file
/// on the other (one at a time on phones). Data files open in the data
/// viewer, notebooks and scripts open as notes or as plain files.
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.info, this.openFile});
  final WorkspaceInfo info;
  final String? openFile;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  Directory? _root;
  String? _selected;
  final _expanded = <String>{};
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.openFile;
    WorkspaceService.instance.folder(widget.info).then((d) {
      if (mounted) setState(() => _root = d);
    });
  }

  void _refresh() => setState(() => _version++);

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  static bool isData(String path) => WorkspaceService.dataExtensions.contains(p.extension(path).toLowerCase());

  void _openPath(String path) {
    if (_wide) {
      setState(() => _selected = path);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => isData(path)
          ? DataViewerPage(path: path, workspace: widget.info)
          : _FilePage(path: path, info: widget.info),
    ));
  }

  Future<void> _saveBack() async {
    final changed = await WorkspaceService.instance.changedFiles(widget.info);
    if (!mounted) return;
    if (changed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing changed: the original folder already matches.'), persist: false));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Save ${changed.length} file${changed.length == 1 ? '' : 's'} back?'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('These files in ${widget.info.source} will be replaced or added:'),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(shrinkWrap: true, children: [
                for (final f in changed) Text(f, style: monoStyle(c, size: 12.5)),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save back')),
        ],
      ),
    );
    if (ok != true) return;
    await WorkspaceService.instance.saveBack(widget.info, changed);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${changed.length} files into the original folder.'), persist: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    final tree = root == null ? const Center(child: CircularProgressIndicator()) : _tree(root);
    return Scaffold(
      appBar: AppBar(
        title: Text('~/${widget.info.name}/', style: monoStyle(context, size: 17, weight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'Refresh files', icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
          if (PlatformHelper.isDesktopOrWeb && !PyodideRuntime.usedHere && root != null)
            IconButton(
              tooltip: 'Terminal in this workspace',
              icon: const Icon(Icons.terminal_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TerminalPage(folder: root))),
            ),
          if (widget.info.source != null)
            TextButton.icon(
              onPressed: _saveBack,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save back'),
            ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => WorkspaceActions.newNotebook(context, widget.info),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New notebook'),
      ),
      body: _wide
          ? Row(children: [
              SizedBox(width: 320, child: tree),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selected == null
                    ? const _Hint()
                    : isData(_selected!)
                        ? DataView(key: ValueKey(_selected), path: _selected!, workspace: widget.info)
                        : _FileView(key: ValueKey(_selected), path: _selected!, info: widget.info),
              ),
            ])
          : tree,
    );
  }

  Widget _tree(Directory root) {
    final color = Theme.of(context).colorScheme;
    return BlocBuilder<NoteBloc, NoteState>(
      builder: (context, noteState) => BlocBuilder<NoteGroupBloc, NoteGroupState>(
        builder: (context, groupState) {
          final group = groupState is NoteGroupLoaded
              ? groupState.groups.where((g) => g.id == widget.info.groupId).firstOrNull
              : null;
          final notes = noteState is NoteLoaded && group != null
              ? noteState.notes.where((n) => group.noteIds.contains(n.id) && !n.isTrashed).toList()
              : const <NoteEntity>[];
          return FutureBuilder<List<_Entry>>(
            key: ValueKey(_version),
            future: _flatten(root),
            builder: (context, snap) {
              final entries = snap.data ?? const <_Entry>[];
              return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                if (notes.isNotEmpty) ...[
                  _Header('notebooks'),
                  for (final n in notes)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.menu_book_rounded, color: color.primary),
                      title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: widget.info.noteFiles[n.id] == null ? null : Text('from ${widget.info.noteFiles[n.id]}'),
                      trailing: widget.info.noteFiles[n.id] == null
                          ? null
                          : IconButton(
                              tooltip: 'Save into ${widget.info.noteFiles[n.id]}',
                              icon: const Icon(Icons.save_outlined, size: 20),
                              onPressed: () async {
                                await WorkspaceActions.saveNoteToFile(context, widget.info, n);
                                _refresh();
                              },
                            ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotePage(note: n))),
                    ),
                ],
                _Header('files'),
                if (snap.connectionState != ConnectionState.done && entries.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                if (snap.connectionState == ConnectionState.done && entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No files yet. Make a notebook with the button below; files your code writes show up here.',
                      style: TextStyle(color: color.onSurfaceVariant),
                    ),
                  ),
                for (final e in entries) _row(e),
              ]);
            },
          );
        },
      ),
    );
  }

  Future<List<_Entry>> _flatten(Directory root) async {
    final out = <_Entry>[];
    Future<void> walk(Directory dir, int depth) async {
      for (final e in await WorkspaceService.list(dir)) {
        out.add(_Entry(e, depth));
        if (e is Directory && _expanded.contains(e.path)) await walk(e, depth + 1);
      }
    }

    await walk(root, 0);
    return out;
  }

  Widget _row(_Entry e) {
    final color = Theme.of(context).colorScheme;
    final name = p.basename(e.entity.path);
    final isDir = e.entity is Directory;
    final open = _expanded.contains(e.entity.path);
    final ext = p.extension(name).toLowerCase();
    final icon = isDir
        ? (open ? Icons.folder_open_rounded : Icons.folder_rounded)
        : isData(name)
            ? Icons.table_chart_rounded
            : ext == '.ipynb'
                ? Icons.menu_book_outlined
                : const {'.png', '.jpg', '.jpeg', '.gif', '.webp'}.contains(ext)
                    ? Icons.image_outlined
                    : Icons.description_outlined;
    final selected = _wide && _selected == e.entity.path;
    return Material(
      color: selected ? color.primaryContainer.withAlpha(120) : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isDir) {
            setState(() {
              open ? _expanded.remove(e.entity.path) : _expanded.add(e.entity.path);
              _version++;
            });
          } else if (ext == '.ipynb') {
            WorkspaceActions.openAsNote(context, widget.info, e.entity.path);
          } else {
            _openPath(e.entity.path);
          }
        },
        onLongPress: isDir ? null : () => _fileMenu(e.entity.path),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14.0 + e.depth * 16, 9, 8, 9),
          child: Row(children: [
            Icon(icon, size: 19, color: isDir ? color.primary : color.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(context, size: 13))),
            if (!isDir)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                onPressed: () => _fileMenu(e.entity.path),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _fileMenu(String path) async {
    final ext = p.extension(path).toLowerCase();
    final runnable = CodeRunner.canRun(languageForFileName(path));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(isData(path) ? 'Open in the data viewer' : 'Open as a file'),
            onTap: () {
              Navigator.pop(c);
              _openPath(path);
            },
          ),
          if (!isData(path))
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Open as a note'),
              subtitle: Text(ext == '.py' ? 'Splits into blocks at # %% lines, like Jupyter cells' : 'Blocks you can run and write about'),
              onTap: () {
                Navigator.pop(c);
                WorkspaceActions.openAsNote(context, widget.info, path);
              },
            ),
          if (isData(path))
            ListTile(
              leading: const Icon(Icons.auto_graph_rounded),
              title: const Text('Analyze in a notebook'),
              subtitle: const Text('First rows, summary, missing values and charts with pandas'),
              onTap: () {
                Navigator.pop(c);
                WorkspaceActions.analyzeInNotebook(context, path, workspace: widget.info);
              },
            ),
          if (runnable)
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Run it'),
              onTap: () {
                Navigator.pop(c);
                _openPath(path);
              },
            ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Save a copy'),
            onTap: () async {
              Navigator.pop(c);
              await saveCopyOf(File(path));
            },
          ),
        ]),
      ),
    );
  }
}

class _Entry {
  _Entry(this.entity, this.depth);
  final FileSystemEntity entity;
  final int depth;
}

class _Header extends StatelessWidget {
  const _Header(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text('// $label',
            style: monoStyle(context, size: 12.5, weight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_open_rounded, size: 44, color: color.primary),
          const SizedBox(height: 12),
          Text('Pick a file on the left', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Data files open as a table. Scripts open as a file you can run, or as a note with ••• > Open as a note. '
            'Notebooks (.ipynb) open as notes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: color.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

class _FilePage extends StatelessWidget {
  const _FilePage({required this.path, required this.info});
  final String path;
  final WorkspaceInfo info;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(p.basename(path), style: monoStyle(context, size: 16, weight: FontWeight.w700))),
        body: _FileView(path: path, info: info),
      );
}

/// A file opened as a file: edit, save (Ctrl+S), run, or open as a note.
class _FileView extends StatefulWidget {
  const _FileView({super.key, required this.path, required this.info});
  final String path;
  final WorkspaceInfo info;

  @override
  State<_FileView> createState() => _FileViewState();
}

class _FileViewState extends State<_FileView> {
  CodeController? _controller;
  String _saved = '';
  String? _error;
  late final Language _language = languageForFileName(widget.path);

  String get _runId => 'file:${widget.path}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      if (await file.length() > 2 * 1024 * 1024) {
        setState(() => _error = 'This file is too big to edit here (over 2 MB).');
        return;
      }
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _saved = text;
        _controller = CodeController(text: text, language: languageInfo(_language).mode)..addListener(_changed);
      });
    } catch (_) {
      if (mounted) setState(() => _error = "This file isn't text, so it can't be edited here. Use ••• > Save a copy.");
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool get _dirty => _controller != null && _controller!.text != _saved;

  Future<void> _save() async {
    final c = _controller;
    if (c == null) return;
    await File(widget.path).writeAsString(c.text);
    setState(() => _saved = c.text);
  }

  Future<void> _run() async {
    await _save();
    RunManager.instance.run(
      blockId: _runId,
      title: p.basename(widget.path),
      spaceKey: widget.info.spaceKey,
      language: _language,
      code: _controller!.text,
      // Phones run Python in a kernel; computers run the file as a script.
      noteId: PyodideRuntime.usedHere ? _runId : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }
    final c = _controller;
    if (c == null) return const Center(child: CircularProgressIndicator());
    final runnable = CodeRunner.canRun(_language);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _run,
      },
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Text(languageInfo(_language).label, style: TextStyle(color: tokens.subtle)),
            if (_dirty) Text('  · not saved', style: TextStyle(color: tokens.pin)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => WorkspaceActions.openAsNote(context, widget.info, widget.path),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('As note'),
            ),
            TextButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
            ),
            if (runnable)
              ListenableBuilder(
                listenable: RunManager.instance,
                builder: (context, _) {
                  final running = RunManager.instance.sessionFor(_runId)?.running ?? false;
                  return FilledButton.icon(
                    onPressed: running ? () => RunManager.instance.sessionFor(_runId)?.stop() : _run,
                    icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                    label: Text(running ? 'Stop' : 'Run'),
                  );
                },
              ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(children: [
              CodeTheme(
                data: CodeThemeData(styles: tokens.codeTheme),
                child: CodeField(
                  controller: c,
                  background: Colors.transparent,
                  textStyle: monoStyle(context, size: 13.5),
                  gutterStyle: GutterStyle(
                    showFoldingHandles: false,
                    showErrors: false,
                    textStyle: monoStyle(context, size: 12, color: tokens.subtle.withAlpha(150)),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: RunManager.instance,
                builder: (context, _) {
                  final s = RunManager.instance.sessionFor(_runId);
                  return s == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.all(8), child: RunPanel(session: s));
                },
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Used by the folder page: is this folder a workspace?
Future<WorkspaceInfo?> workspaceFor(String groupId) => WorkspaceService.instance.get(groupId);
