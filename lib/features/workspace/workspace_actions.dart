import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/util/platform_helper.dart';
import '../notebook/ipynb_import.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import '../notes/presentation/bloc/note_bloc.dart';
import '../notes/presentation/bloc/note_event.dart';
import '../notes/presentation/bloc/note_state.dart';
import '../notes/presentation/bloc/note_group_bloc.dart';
import '../notes/presentation/bloc/note_group_event.dart';
import '../notes/presentation/bloc/note_group_state.dart';
import '../notes/presentation/pages/note_page.dart';
import 'workspace_page.dart';
import 'workspace_service.dart';

/// Opening folders and files as workspaces, and turning files into notes
/// (and notes back into files).
class WorkspaceActions {
  WorkspaceActions._();

  static const _uuid = Uuid();
  static final _ws = WorkspaceService.instance;

  static void _say(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), persist: false));
  }

  /// A new CodeNote folder that is also a workspace.
  static Future<WorkspaceInfo> _create(BuildContext context, String name, {String? source}) async {
    final group = NoteGroupEntity(id: _uuid.v4(), name: name, noteIds: const [], lastModified: DateTime.now());
    final bloc = context.read<NoteGroupBloc>();
    bloc.add(AddGroupEvent(group));
    final info = WorkspaceInfo(groupId: group.id, name: name, source: source);
    await _ws.save(info);
    // Wait until the folder exists, so notes added next land in it.
    await _group(bloc, group.id);
    return info;
  }

  static Future<NoteGroupEntity?> _group(NoteGroupBloc bloc, String id) async {
    NoteGroupEntity? find(Object state) =>
        state is NoteGroupLoaded ? state.groups.where((g) => g.id == id).firstOrNull : null;
    final now = find(bloc.state);
    if (now != null) return now;
    try {
      final state = await bloc.stream.firstWhere((s) => find(s) != null).timeout(const Duration(seconds: 3));
      return find(state);
    } catch (_) {
      return null;
    }
  }

  /// Computers: pick a folder. Phones: pick files (CSV, Excel, notebooks,
  /// scripts). Either way they're copied into a new workspace's sandbox.
  static Future<void> openWorkspace(BuildContext context) async {
    if (PlatformHelper.isDesktopOrWeb) {
      final dir = await getDirectoryPath(confirmButtonText: 'Open as workspace');
      if (dir == null || !context.mounted) return;
      final info = await _create(context, p.basename(dir), source: dir);
      final target = await _ws.folder(info);
      if (!context.mounted) return;
      final result = await _withProgress(context, 'Copying files into the sandbox…',
          () => _ws.copyFolder(dir, target));
      if (!context.mounted) return;
      if (result.skipped > 0) {
        _say(context, 'Copied ${result.files} files. Skipped ${result.skipped} (caches, git, or over the size limit).');
      }
      _open(context, info);
      return;
    }
    final files = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: 'Any file')]);
    if (files.isEmpty || !context.mounted) return;
    final name = files.length == 1 ? p.basenameWithoutExtension(files.first.name) : 'workspace';
    final info = await _create(context, name);
    final target = await _ws.folder(info);
    await _ws.copyFiles([for (final f in files) f.path], [for (final f in files) f.name], target);
    if (!context.mounted) return;
    // One data file: straight to the viewer.
    _open(context, info, file: files.length == 1 ? p.join(target.path, files.first.name) : null);
  }

  /// Opens one data file (CSV, Excel, JSON, Parquet) in a new workspace.
  static Future<void> openDataFile(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Data', extensions: ['csv', 'tsv', 'json', 'jsonl', 'xlsx', 'xls', 'parquet', 'txt']),
    ]);
    if (file == null || !context.mounted) return;
    final info = await _create(context, p.basenameWithoutExtension(file.name));
    final target = await _ws.folder(info);
    await _ws.copyFiles([file.path], [file.name], target);
    if (!context.mounted) return;
    _open(context, info, file: p.join(target.path, file.name));
  }

  /// A data file shared into CodeNote or opened from the file manager.
  static Future<void> openDataPath(BuildContext context, String path) async {
    final info = await _create(context, p.basenameWithoutExtension(path));
    final target = await _ws.folder(info);
    final copy = p.join(target.path, p.basename(path));
    await File(path).copy(copy);
    if (context.mounted) _open(context, info, file: copy);
  }

  static void _open(BuildContext context, WorkspaceInfo info, {String? file}) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkspacePage(info: info, openFile: file)));
  }

  static Future<T> _withProgress<T>(BuildContext context, String label, Future<T> Function() work) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
        ]),
      ),
    );
    try {
      return await work();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ---------- notes ----------

  /// Adds [note] to the workspace's folder, saves it and opens it.
  static Future<void> _addNote(BuildContext context, WorkspaceInfo info, NoteEntity note) async {
    context.read<NoteBloc>().add(AddNoteEvent(note));
    final bloc = context.read<NoteGroupBloc>();
    final group = await _group(bloc, info.groupId);
    if (group != null) {
      bloc.add(UpdateGroupEvent(group.copyWith(noteIds: [...group.noteIds, note.id], lastModified: DateTime.now())));
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotePage(note: note)));
  }

  /// Opens a file as a note in the workspace: notebooks become cells,
  /// `.py` splits at `# %%`, Markdown stays Markdown. The note remembers
  /// its file, so it can be saved back into it.
  static Future<void> openAsNote(BuildContext context, WorkspaceInfo info, String path) async {
    final root = await _ws.folder(info);
    final rel = p.relative(path, from: root.path);
    final existing = info.noteFiles.entries.where((e) => e.value == rel).map((e) => e.key).firstOrNull;
    if (!context.mounted) return;
    if (existing != null) {
      final state = context.read<NoteBloc>().state;
      final note = state is NoteLoaded ? state.notes.where((n) => n.id == existing).firstOrNull : null;
      if (note != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotePage(note: note)));
        return;
      }
    }
    List<BlockEntity> blocks;
    try {
      if (p.extension(path).toLowerCase() == '.ipynb') {
        blocks = (await IpynbImport.fromFile(path)).blocks;
      } else {
        blocks = FileNotes.blocksFor(path, await File(path).readAsString());
      }
    } catch (e) {
      if (context.mounted) _say(context, "Couldn't open it as a note: $e");
      return;
    }
    final note = NoteEntity(
      id: _uuid.v4(),
      title: p.basename(path),
      tags: const ['workspace'],
      lastModified: DateTime.now(),
      blocks: blocks.isEmpty ? [CodeBlockEntity(id: _uuid.v4(), text: '', language: Language.python)] : blocks,
    );
    info.noteFiles[note.id] = rel;
    await _ws.save(info);
    if (context.mounted) await _addNote(context, info, note);
  }

  /// Writes a note back into the file it came from.
  static Future<void> saveNoteToFile(BuildContext context, WorkspaceInfo info, NoteEntity note) async {
    final rel = info.noteFiles[note.id];
    if (rel == null) return;
    final root = await _ws.folder(info);
    await File(p.join(root.path, rel)).writeAsString(FileNotes.textFor(rel, note));
    if (context.mounted) _say(context, 'Saved into $rel.');
  }

  /// A new notebook that reads [path] with pandas and shows the first
  /// rows, a summary, what's missing and charts.
  static Future<void> analyzeInNotebook(BuildContext context, String path, {WorkspaceInfo? workspace}) async {
    var info = workspace;
    var file = path;
    if (info == null) {
      info = await _create(context, p.basenameWithoutExtension(path));
      final target = await _ws.folder(info);
      file = p.join(target.path, p.basename(path));
      await File(path).copy(file);
    }
    final root = await _ws.folder(info);
    final rel = p.relative(file, from: root.path).replaceAll(r'\', '/');
    final ext = p.extension(file).toLowerCase();
    final read = switch (ext) {
      '.xlsx' || '.xls' => 'pd.read_excel("$rel")',
      '.parquet' => 'pd.read_parquet("$rel")',
      '.json' => 'pd.read_json("$rel")',
      '.jsonl' => 'pd.read_json("$rel", lines=True)',
      '.tsv' => 'pd.read_csv("$rel", sep="\\t")',
      _ => 'pd.read_csv("$rel", sep=None, engine="python")',
    };
    final note = NoteEntity(
      id: _uuid.v4(),
      title: 'Analysis of ${p.basename(file)}',
      tags: const ['analysis', 'workspace'],
      lastModified: DateTime.now(),
      blocks: [
        MarkdownBlockEntity(
          id: _uuid.v4(),
          text: '## ${p.basename(file)}\n'
              'Press **▶ Run note** to run every block, or ▶ on one block. '
              'Blocks share variables, so `df` is there in every block.',
        ),
        CodeBlockEntity(id: _uuid.v4(), language: Language.python, text: ('import pandas as pd\n\ndf = $read\ndf.head(20)')),
        MarkdownBlockEntity(id: _uuid.v4(), text: '### Size and column types'),
        CodeBlockEntity(id: _uuid.v4(), language: Language.python, text: ('print(f"{df.shape[0]:,} rows, {df.shape[1]} columns")\ndf.dtypes.to_frame("type")')),
        MarkdownBlockEntity(id: _uuid.v4(), text: '### Summary of every column'),
        CodeBlockEntity(id: _uuid.v4(), language: Language.python, text: ('df.describe(include="all").T')),
        MarkdownBlockEntity(id: _uuid.v4(), text: '### What is missing'),
        CodeBlockEntity(
          id: _uuid.v4(),
          language: Language.python,
          text: ('missing = df.isna().sum()\nmissing[missing > 0].sort_values(ascending=False).to_frame("missing")'),
        ),
        MarkdownBlockEntity(id: _uuid.v4(), text: '### How the numbers spread'),
        CodeBlockEntity(
          id: _uuid.v4(),
          language: Language.python,
          text: ('import matplotlib.pyplot as plt\n\n'
              'numbers = df.select_dtypes("number")\n'
              'if numbers.empty:\n'
              '    print("No number columns to chart.")\n'
              'else:\n'
              '    numbers.hist(figsize=(10, 6), bins=30)\n'
              '    plt.tight_layout()\n'
              '    plt.show()'),
        ),
        MarkdownBlockEntity(id: _uuid.v4(), text: '### Which numbers move together'),
        CodeBlockEntity(
          id: _uuid.v4(),
          language: Language.python,
          text: ('if numbers.shape[1] > 1:\n'
              '    corr = numbers.corr()\n'
              '    fig, ax = plt.subplots(figsize=(7, 6))\n'
              '    im = ax.imshow(corr, cmap="coolwarm", vmin=-1, vmax=1)\n'
              '    ax.set_xticks(range(len(corr)), corr.columns, rotation=45, ha="right")\n'
              '    ax.set_yticks(range(len(corr)), corr.columns)\n'
              '    fig.colorbar(im)\n'
              '    plt.show()\n'
              '    display(corr.round(2))'),
        ),
      ],
    );
    if (!context.mounted) return;
    await _addNote(context, info, note);
  }

  /// A new empty notebook in the workspace.
  static Future<void> newNotebook(BuildContext context, WorkspaceInfo info) {
    return _addNote(
      context,
      info,
      NoteEntity(
        id: _uuid.v4(),
        title: 'Notebook',
        tags: const ['workspace'],
        lastModified: DateTime.now(),
        blocks: [
          MarkdownBlockEntity(id: _uuid.v4(), text: 'Files in this workspace are next to your code: open them by name.'),
          CodeBlockEntity(id: _uuid.v4(), language: Language.python, text: 'import os\nsorted(os.listdir("."))'),
        ],
      ),
    );
  }
}
