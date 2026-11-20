import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../constants/themes.dart';
import '../../../../core/util/image_helper.dart';
import '../../../../core/util/note_share_helper.dart';
import '../../../../widgets/note_navigation_bar.dart';
import '../../../reminders/reminder_service.dart';
import '../../../templates/templates.dart';
import '../../../gist/gist_page.dart';
import '../../../backup/codenote_files.dart';
import '../../../notebook/html_report.dart';
import '../../../notebook/ipynb_import.dart';
import '../../../runner/notebook_focus.dart';
import '../../../miniapps/mini_app_storage.dart';
import '../../../runner/note_scope.dart';
import '../../../runner/sandbox.dart';
import '../../../runner/code_runner.dart';
import '../../../runner/run_manager.dart';
import '../../../runner/running_indicator.dart';
import '../../domain/entities/block.dart';
import '../../domain/entities/language.dart';
import '../../domain/entities/note.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../bloc/note_group_bloc.dart';
import '../bloc/note_group_event.dart';
import '../bloc/note_group_state.dart';
import '../bloc/note_state.dart';
import '../widgets/block_widget_factory.dart';
import 'scan_document_page.dart';
import 'web_preview_page.dart';

enum _SaveStatus { saved, editing }

class NotePage extends StatefulWidget {
  final NoteEntity note;

  /// When set, the note is added to this folder as soon as it's first saved.
  final String? groupId;

  const NotePage({super.key, required this.note, this.groupId});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  static const _uuid = Uuid();
  static const _saveDelay = Duration(milliseconds: 600);

  late final TextEditingController _titleController;
  final _scroll = ScrollController();
  final _primaryKey = GlobalKey();
  final TextEditingController _tagController = TextEditingController();
  late final NoteBloc _noteBloc;
  late final NoteGroupBloc _groupBloc;

  late List<BlockEntity> _blocks;
  late List<String> _tags;
  late bool _isPinned;
  late bool _isArchived;
  late bool _isTrashed;
  DateTime? _trashTimestamp;
  NoteReminderEntity? _reminder;
  late DateTime _lastSaved;

  /// True until the note has been saved once. Empty new notes are never
  /// saved, so opening "new note" and going back leaves nothing behind.
  late bool _isNew;
  bool _dirty = false;
  bool _disposing = false;
  Timer? _saveTimer;

  /// Shown under the title. A notifier, so typing doesn't rebuild the page.
  final ValueNotifier<_SaveStatus> _status = ValueNotifier(_SaveStatus.saved);

  @override
  void initState() {
    super.initState();
    _noteBloc = context.read<NoteBloc>();
    _groupBloc = context.read<NoteGroupBloc>();
    final note = widget.note;
    _titleController = TextEditingController(text: note.title);
    _blocks = List.of(note.blocks);
    _tags = List.of(note.tags);
    _isPinned = note.isPinned;
    _isArchived = note.isArchived;
    _isTrashed = note.isTrashed;
    _trashTimestamp = note.trashTimestamp;
    _reminder = note.reminder;
    _lastSaved = note.lastModified;

    final state = _noteBloc.state;
    _isNew = !(state is NoteLoaded && state.notes.any((n) => n.id == note.id));

    // A brand-new note starts with one text block, ready to type.
    if (_isNew && _blocks.isEmpty) {
      _blocks.add(NoteBlockEntity(id: _uuid.v4()));
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _disposing = true;
    // Save anything typed in the last moment before leaving.
    _flush();
    _titleController.dispose();
    _scroll.dispose();
    _tagController.dispose();
    _status.dispose();
    super.dispose();
  }

  // ─── Saving ─────────────────────────────────────────────

  bool get _isEmpty =>
      _titleController.text.trim().isEmpty &&
      _tags.isEmpty &&
      _reminder == null &&
      _blocks.every((b) => b is! ImageBlockEntity && (b.text ?? '').trim().isEmpty);

  /// The note's ★ primary code block, if it has one.
  CodeBlockEntity? get _primaryBlock {
    for (final b in _blocks) {
      if (b is CodeBlockEntity && b.runRole == RunRole.main) return b;
    }
    return null;
  }

  /// Scrolls to the primary block. Blocks far down aren't built yet, so
  /// scroll a screen at a time until it appears.
  Future<void> _showPrimary() async {
    for (var i = 0; i < 40; i++) {
      final ctx = _primaryKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.1);
        return;
      }
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.pixels >= pos.maxScrollExtent) return;
      _scroll.jumpTo((pos.pixels + pos.viewportDimension * 0.8).clamp(0, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  bool get _hasRunnableCode => RunManager.folderBlocks(_currentNote()).isNotEmpty;

  Future<void> _runNote() async {
    final messenger = ScaffoldMessenger.of(context);
    final problem = await RunManager.instance.runNote(_currentNote(), _spaceKey());
    if (problem != null && problem != 'Stopped.') {
      messenger.showSnackBar(SnackBar(content: Text(problem), persist: false));
    }
  }

  /// Side margins: roomy on wide desktop windows, tight on phones.
  double _sidePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 1400 ? 48 : w >= 900 ? 32 : 20;
  }

  /// This note's sandbox: shared with the other notes in its folder.
  String _spaceKey() {
    final state = context.read<NoteGroupBloc>().state;
    String? folderId = widget.groupId;
    if (state is NoteGroupLoaded) {
      for (final g in state.groups) {
        if (g.noteIds.contains(widget.note.id)) {
          folderId = g.id;
          break;
        }
      }
    }
    return Sandbox.keyFor(noteId: widget.note.id, folderId: folderId);
  }

  Future<void> _resetAppData() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset saved app data?'),
        content: const Text(
            'Everything this page saved (scores, settings, lists) is deleted. The note itself stays.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await MiniAppStorage.instance.clear(widget.note.id);
    messenger.showSnackBar(const SnackBar(content: Text('Saved app data cleared.'), persist: false));
  }

  Future<void> _saveAsTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    await Templates.saveAsTemplate(_currentNote());
    messenger.showSnackBar(const SnackBar(
      content: Text('Saved as a template. Find it under "New from template".'),
      persist: false,
      duration: Duration(seconds: 4),
    ));
  }

  NoteEntity _currentNote() => widget.note.copyWith(
        title: _titleController.text,
        tags: List.of(_tags),
        blocks: List.of(_blocks),
        lastModified: DateTime.now(),
        isPinned: _isPinned,
        isArchived: _isArchived,
        isTrashed: _isTrashed,
        trashTimestamp: _trashTimestamp,
        clearTrashTimestamp: _trashTimestamp == null,
        reminder: _reminder,
        clearReminder: _reminder == null,
      );

  /// Marks the note as changed and saves shortly after typing stops.
  void _changed() {
    _dirty = true;
    if (!_disposing) _status.value = _SaveStatus.editing;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _flush);
  }

  /// Saves now if anything changed.
  void _flush() {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    if (_isNew && _isEmpty) return;
    final note = _currentNote();
    _noteBloc.add(UpdateNoteEvent(note));
    if (_isNew) _addToStartingGroup();
    _isNew = false;
    _lastSaved = note.lastModified;
    if (!_disposing) _status.value = _SaveStatus.saved;
  }

  /// A note created inside a folder joins that folder on its first save.
  void _addToStartingGroup() {
    final groupId = widget.groupId;
    final state = _groupBloc.state;
    if (groupId == null || state is! NoteGroupLoaded) return;
    for (final group in state.groups) {
      if (group.id == groupId && !group.noteIds.contains(widget.note.id)) {
        _groupBloc.add(UpdateGroupEvent(
            group.copyWith(noteIds: [...group.noteIds, widget.note.id])));
      }
    }
  }

  // ─── Blocks ─────────────────────────────────────────────

  void _addBlock(BlockEntity block) {
    setState(() => _blocks.add(block));
    _changed();
  }

  void _addImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null) return;
    final path = await ImageHelper.persistImage(image.path);
    if (!mounted) return;
    _addBlock(ImageBlockEntity(id: _uuid.v4(), imagePath: path));
  }

  void _scanDoc() async {
    final result = await Navigator.of(context).push(MaterialPageRoute<BlockEntity>(
      builder: (context) => ScanDocument(
        onPressed: _deleteBlock,
        moveDown: _moveDown,
        moveUp: _moveUp,
      ),
    ));
    if (result != null && mounted) _addBlock(result);
  }

  void _deleteBlock(String id) {
    final index = _blocks.indexWhere((b) => b.id == id);
    if (index == -1) return;
    final removed = _blocks[index];
    setState(() => _blocks.removeAt(index));
    _changed();

    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Block deleted'),
        persist: false, // auto-hide even with an Undo button
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() => _blocks.insert(index.clamp(0, _blocks.length), removed));
            _changed();
          },
        ),
      ));
  }

  /// Saves (desktop) or shares (phone) an export of this note.
  Future<void> _export(String text, String ext, String mime, String label) async {
    final title = _titleController.text.trim().isEmpty ? 'note' : _titleController.text.trim();
    final safe = title.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '').trim().replaceAll(' ', '-');
    final saved = await NoteShareHelper.saveOrShareBytes(
      Uint8List.fromList(utf8.encode(text)),
      fileName: '${safe.isEmpty ? 'note' : safe}.$ext',
      mimeType: mime,
      typeLabel: label,
    );
    if (saved != null) _toast('Saved $label.');
  }

  // ---------- Jupyter-style keyboard moves between code blocks ----------

  late final _notebook = NotebookActions(
    next: _nbNext,
    previous: _nbPrevious,
    insert: _nbInsert,
    toMarkdown: _nbToMarkdown,
    delete: _nbDelete,
  );

  String? _nbNeighbour(String id, int step) {
    final index = _blocks.indexWhere((b) => b.id == id);
    if (index == -1) return null;
    for (var i = index + step; i >= 0 && i < _blocks.length; i += step) {
      if (_blocks[i] is CodeBlockEntity) return _blocks[i].id;
    }
    return null;
  }

  void _nbNext(String id) {
    final next = _nbNeighbour(id, 1);
    if (next != null) {
      NotebookFocus.focus(next, edit: false);
    } else {
      _nbInsert(id, above: false);
    }
  }

  void _nbPrevious(String id) {
    final previous = _nbNeighbour(id, -1);
    if (previous != null) NotebookFocus.focus(previous, edit: false);
  }

  void _nbInsert(String id, {required bool above}) {
    final index = _blocks.indexWhere((b) => b.id == id);
    final current = index == -1 ? null : _blocks[index];
    final block = CodeBlockEntity(
      id: _uuid.v4(),
      text: '',
      language: current is CodeBlockEntity ? current.language : Language.python,
    );
    setState(() => _blocks.insert(index == -1 ? _blocks.length : (above ? index : index + 1), block));
    _changed();
    NotebookFocus.focus(block.id);
  }

  void _nbToMarkdown(String id) {
    final index = _blocks.indexWhere((b) => b.id == id);
    if (index == -1) return;
    setState(() => _blocks[index] = MarkdownBlockEntity(id: _uuid.v4(), text: _blocks[index].text ?? ''));
    _changed();
  }

  void _nbDelete(String id) {
    final next = _nbNeighbour(id, 1) ?? _nbNeighbour(id, -1);
    _deleteBlock(id);
    if (next != null) NotebookFocus.focus(next, edit: false);
  }

  /// Puts [block] right after the block with [afterId] (AI answers).
  void _insertAfter(String afterId, BlockEntity block) {
    final index = _blocks.indexWhere((b) => b.id == afterId);
    setState(() => _blocks.insert(index == -1 ? _blocks.length : index + 1, block));
    _changed();
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
    });
    _changed();
  }

  void _moveUp(String id) => _move(id, -1);
  void _moveDown(String id) => _move(id, 1);

  void _move(String id, int by) {
    final index = _blocks.indexWhere((b) => b.id == id);
    final target = index + by;
    if (index == -1 || target < 0 || target >= _blocks.length) return;
    setState(() {
      final block = _blocks.removeAt(index);
      _blocks.insert(target, block);
    });
    _changed();
  }

  /// Typing inside a block: update the data, but don't rebuild the page.
  /// The block already shows what was typed.
  void _onBlockChanged(BlockEntity updated) {
    final index = _blocks.indexWhere((b) => b.id == updated.id);
    if (index == -1) return;
    final couldPreview = WebPreview.canPreview(_blocks);
    final wasWebPage = CodeRunner.isWebPageNote(_blocks);
    _blocks[index] = updated;
    // Only one main block per note: picking a new one clears the old one.
    if (updated is CodeBlockEntity && updated.runRole == RunRole.main) {
      var demoted = false;
      for (var i = 0; i < _blocks.length; i++) {
        final b = _blocks[i];
        if (i != index && b is CodeBlockEntity && b.runRole == RunRole.main) {
          _blocks[i] = b.copyWith(runRole: RunRole.normal);
          demoted = true;
        }
      }
      if (demoted) setState(() {});
    }
    // Rebuild only when the ▶ preview button should appear or disappear.
    if (couldPreview != WebPreview.canPreview(_blocks) || wasWebPage != CodeRunner.isWebPageNote(_blocks)) {
      setState(() {});
    }
    _changed();
  }

  // ─── Tags ───────────────────────────────────────────────

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '').replaceAll(' ', '-');
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
    _changed();
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
    _changed();
  }

  // ─── Menu actions ───────────────────────────────────────

  void _togglePin() {
    HapticFeedback.lightImpact();
    setState(() => _isPinned = !_isPinned);
    _changed();
  }

  void _toggleArchive() {
    setState(() {
      _isArchived = !_isArchived;
      if (_isArchived) _isPinned = false;
    });
    _dirty = true;
    _flush();
    if (_isArchived) {
      Navigator.pop(context);
      _toast('Archived');
    }
  }

  void _moveToTrash() {
    _isTrashed = true;
    _isPinned = false;
    _trashTimestamp = DateTime.now();
    _dirty = true;
    if (_isNew && _isEmpty) {
      // Nothing worth keeping; just leave.
      _dirty = false;
    } else {
      _flush();
    }
    Navigator.pop(context);
    _toast('Moved to trash. It stays there for 30 days.');
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showReminderDialog() async {
    final now = DateTime.now();
    final initial = _reminder?.dateTime ?? now.add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) return;

    final when = DateTime(pickedDate.year, pickedDate.month, pickedDate.day,
        pickedTime.hour, pickedTime.minute);
    if (when.isBefore(DateTime.now())) {
      _toast('Pick a time in the future.');
      return;
    }

    final messageController = TextEditingController(text: _reminder?.message);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reminder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMMMEd().add_jm().format(when),
                style: monoStyle(dialogContext,
                    size: 13, color: Theme.of(dialogContext).colorScheme.primary)),
            const SizedBox(height: 6),
            Text(
              ReminderService.systemNotifications
                  ? "You'll get a notification at that time, even if CodeNote is closed."
                  : 'A reminder pops up at that time while CodeNote is open.',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: dialogContext.tokens.subtle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'What should we remind you?'),
            ),
          ],
        ),
        actions: [
          if (_reminder != null)
            TextButton(
              onPressed: () {
                setState(() => _reminder = null);
                _changed();
                Navigator.pop(dialogContext);
              },
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ReminderService.instance.requestPermission();
              setState(() => _reminder = NoteReminderEntity(
                    dateTime: when,
                    message: messageController.text.trim(),
                  ));
              _changed();
              Navigator.pop(dialogContext);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _shareNote() {
    final note = _currentNote();
    final languages = _blocks
        .whereType<CodeBlockEntity>()
        .map((e) => e.language)
        .toSet()
        .toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('CodeNote file (.codenote)'),
              subtitle: const Text('Everything: blocks, images, run order and app data. Opens in CodeNote.'),
              onTap: () {
                Navigator.pop(sheetContext);
                CodenoteFiles.shareNote(context, _currentNote());
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy as text'),
              onTap: () {
                NoteShareHelper.copyToClipboard(
                    NoteShareHelper.formatNoteAsText(note));
                Navigator.pop(sheetContext);
                _toast('Copied. Ready to paste.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Share as .txt'),
              onTap: () {
                NoteShareHelper.shareAsTxt(note);
                Navigator.pop(sheetContext);
              },
            ),
            for (final lang in languages)
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: Text('Share as a ${lang.name} file'),
                onTap: () {
                  NoteShareHelper.shareNoteAsFile(note, lang);
                  Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _addToGroup() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => BlocBuilder<NoteGroupBloc, NoteGroupState>(
        builder: (context, state) {
          if (state is! NoteGroupLoaded) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.groups.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Text(
                'No groups yet. Create one from the home screen with the folder button.',
                style: TextStyle(color: context.tokens.subtle),
              ),
            );
          }
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Add to group',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final group in state.groups)
                  CheckboxListTile(
                    value: group.noteIds.contains(widget.note.id),
                    secondary: const Icon(Icons.folder_outlined),
                    title: Text(group.name),
                    onChanged: (checked) {
                      // Make sure the note exists before a group points to it.
                      _dirty = true;
                      _flush();
                      final ids = List<String>.of(group.noteIds);
                      if (checked == true) {
                        if (!ids.contains(widget.note.id)) ids.add(widget.note.id);
                      } else {
                        ids.remove(widget.note.id);
                      }
                      _groupBloc
                          .add(UpdateGroupEvent(group.copyWith(noteIds: ids)));
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _flush(),
      child: Scaffold(
        appBar: AppBar(
          actions: [
            if (_hasRunnableCode)
              ListenableBuilder(
                listenable: RunManager.instance,
                builder: (context, _) {
                  final note = _currentNote();
                  final running = RunManager.instance.noteStatus.containsKey(note.id) ||
                      RunManager.instance.anyRunning(note.blocks.map((b) => b.id));
                  return IconButton(
                    tooltip: running ? 'Running · tap to stop this note' : 'Run note (blocks in order, primary last)',
                    icon: RunButtonIcon(running: running, size: 22),
                    onPressed: () => running ? RunManager.instance.stopNote(note) : _runNote(),
                  );
                },
              ),
            if (WebPreview.canPreview(_blocks))
              IconButton(
                tooltip: 'Open the web page (HTML, CSS, JS)',
                icon: Icon(Icons.open_in_browser_rounded, color: tokens.success),
                onPressed: () => WebPreview.open(context, _currentNote(), spaceKey: _spaceKey()),
              ),
            IconButton(
              tooltip: _reminder == null ? 'Add reminder' : 'Edit reminder',
              icon: Icon(
                _reminder == null
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: _reminder == null ? null : tokens.pin,
              ),
              onPressed: _showReminderDialog,
            ),
            IconButton(
              tooltip: _isPinned ? 'Unpin' : 'Pin to top',
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _isPinned ? tokens.pin : null,
              ),
              onPressed: _togglePin,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                switch (value) {
                  case 'group':
                    _addToGroup();
                  case 'share':
                    _shareNote();
                  case 'template':
                    _saveAsTemplate();
                  case 'gist':
                    exportNoteToGist(context, _currentNote());
                  case 'codenote':
                    CodenoteFiles.shareNote(context, _currentNote());
                  case 'ipynb':
                    _export(
                      IpynbExport.fromNote(_currentNote(), readImage: (path) {
                        try {
                          return File(path).readAsBytesSync();
                        } catch (_) {
                          return null;
                        }
                      }),
                      'ipynb',
                      'application/x-ipynb+json',
                      'Jupyter notebook',
                    );
                  case 'report':
                    _export(
                      HtmlReport.fromNote(_currentNote(), readImage: HtmlReport.readFile),
                      'html',
                      'text/html',
                      'HTML report',
                    );
                  case 'shortcuts':
                    showNotebookShortcuts(context);
                  case 'appdata':
                    _resetAppData();
                  case 'archive':
                    _toggleArchive();
                  case 'trash':
                    _moveToTrash();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'group',
                  child: ListTile(
                    leading: Icon(Icons.folder_outlined),
                    title: Text('Add to group'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_rounded),
                    title: Text('Share'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'template',
                  child: ListTile(
                    leading: Icon(Icons.dashboard_customize_outlined),
                    title: Text('Save as template'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (WebPreview.canPreview(_blocks))
                  const PopupMenuItem(
                    value: 'appdata',
                    child: ListTile(
                      leading: Icon(Icons.restart_alt_rounded),
                      title: Text('Reset saved app data'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'codenote',
                  child: ListTile(
                    leading: Icon(Icons.description_outlined),
                    title: Text('Share as .codenote file'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'ipynb',
                  child: ListTile(
                    leading: Icon(Icons.menu_book_outlined),
                    title: Text('Export as Jupyter notebook'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: Icon(Icons.article_outlined),
                    title: Text('Export as HTML report'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'shortcuts',
                  child: ListTile(
                    leading: Icon(Icons.keyboard_outlined),
                    title: Text('Keyboard shortcuts'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'gist',
                  child: ListTile(
                    leading: Icon(Icons.upload_rounded),
                    title: Text('Upload as gist'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                    leading: Icon(_isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined),
                    title: Text(_isArchived ? 'Unarchive' : 'Archive'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'trash',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: color.error),
                    title: Text('Move to trash', style: TextStyle(color: color.error)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: NoteScope(
          noteId: widget.note.id,
          spaceKey: _spaceKey(),
          title: _titleController.text,
          isWebPage: CodeRunner.isWebPageNote(_blocks),
          notebook: _notebook,
          child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  // Full width on desktop, like an editor; the side padding grows instead.
                  constraints: const BoxConstraints(maxWidth: double.infinity),
                  child: CustomScrollView(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                     SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: _sidePadding(context)),
                      sliver: SliverList.list(children: [
                      ValueListenableBuilder<_SaveStatus>(
                        valueListenable: _status,
                        builder: (context, status, _) => Row(
                          children: [
                            Icon(
                              status == _SaveStatus.saved
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.edit_outlined,
                              size: 13,
                              color: status == _SaveStatus.saved
                                  ? tokens.success
                                  : tokens.subtle,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status == _SaveStatus.saved
                                  ? (_isNew
                                      ? 'new note'
                                      : 'saved · ${DateFormat.MMMd().add_jm().format(_lastSaved)}')
                                  : 'editing…',
                              style: monoStyle(context,
                                  size: 11, color: tokens.subtle),
                            ),
                          ],
                        ),
                      ),
                      TextField(
                        controller: _titleController,
                        autofocus: _isNew,
                        textCapitalization: TextCapitalization.sentences,
                        style: textTheme.headlineMedium,
                        decoration: InputDecoration(
                          hintText: 'Untitled',
                          filled: false,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintStyle: textTheme.headlineMedium?.copyWith(
                            color: color.onSurfaceVariant.withAlpha(110),
                          ),
                        ),
                        onChanged: (_) => _changed(),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_primaryBlock != null)
                            ActionChip(
                              avatar: Icon(Icons.star_rounded, size: 16, color: tokens.pin),
                              label: Text('primary', style: monoStyle(context, size: 12)),
                              tooltip: 'Jump to the primary block',
                              visualDensity: VisualDensity.compact,
                              onPressed: _showPrimary,
                            ),
                          for (final tag in _tags)
                            InputChip(
                              label: Text('#$tag'),
                              onDeleted: () => _removeTag(tag),
                              deleteButtonTooltipMessage: 'Remove #$tag',
                              deleteIcon: const Icon(Icons.close_rounded, size: 14),
                              visualDensity: VisualDensity.compact,
                            ),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _tagController,
                              style: monoStyle(context, size: 12),
                              decoration: InputDecoration(
                                hintText: '+ tag',
                                hintStyle: monoStyle(context,
                                    size: 12, color: tokens.subtle),
                                filled: false,
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: _addTag,
                            ),
                          ),
                        ],
                      ),
                      if (_reminder != null) ...[
                        const SizedBox(height: 10),
                        _ReminderChip(
                          reminder: _reminder!,
                          onTap: _showReminderDialog,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Divider(color: color.outlineVariant),
                      const SizedBox(height: 4),
                      ]),
                     ),
                      // Blocks: drag the grip on a block's header to reorder.
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(_sidePadding(context), 0, _sidePadding(context), 120),
                        sliver: _blocks.isEmpty
                            ? SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 32),
                                  child: Text(
                                    '// empty note. Add a block below.',
                                    textAlign: TextAlign.center,
                                    style: monoStyle(context, color: tokens.subtle),
                                  ),
                                ),
                              )
                            : SliverReorderableList(
                                itemCount: _blocks.length,
                                onReorder: _reorder,
                                proxyDecorator: (child, index, animation) =>
                                    Material(
                                  elevation: 6,
                                  color: color.surfaceContainer,
                                  borderRadius:
                                      BorderRadius.circular(AppBrand.radius),
                                  child: child,
                                ),
                                itemBuilder: (context, index) {
                                  final block = _blocks[index];
                                  return KeyedSubtree(
                                    key: ValueKey('reorder_${block.id}'),
                                    child: KeyedSubtree(
                                    key: block.id == _primaryBlock?.id ? _primaryKey : null,
                                    child: BlockWidgetFactory.createBlockWidget(
                                      entity: block,
                                      onChanged: _onBlockChanged,
                                      onDelete: _deleteBlock,
                                      onMoveUp: index == 0 ? null : _moveUp,
                                      onMoveDown: index == _blocks.length - 1
                                          ? null
                                          : _moveDown,
                                      onInsertAfter: _insertAfter,
                                      dragHandle: _blocks.length < 2
                                          ? null
                                          : ReorderableDragStartListener(
                                              index: index,
                                              child: Tooltip(
                                                message: 'Drag to move',
                                                child: MouseRegion(
                                                  cursor: SystemMouseCursors.grab,
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(
                                                        right: 4),
                                                    child: Icon(
                                                      Icons.drag_indicator_rounded,
                                                      size: 18,
                                                      color: tokens.subtle,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            NoteNavigationBar(
              addText: () => _addBlock(NoteBlockEntity(id: _uuid.v4())),
              addCode: () => _addBlock(CodeBlockEntity(id: _uuid.v4())),
              addMarkdown: () => _addBlock(MarkdownBlockEntity(id: _uuid.v4())),
              addImage: _addImage,
              // Text recognition (ML Kit) only exists on phones.
              scanDoc: !kIsWeb && (Platform.isAndroid || Platform.isIOS)
                  ? _scanDoc
                  : null,
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  const _ReminderChip({required this.reminder, required this.onTap});
  final NoteReminderEntity reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pin = context.tokens.pin;
    final when = DateFormat.MMMEd().add_jm().format(reminder.dateTime);
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: Icon(Icons.alarm_rounded, size: 16, color: pin),
        label: Text(
          reminder.message.isEmpty ? when : '$when · ${reminder.message}',
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: onTap,
        tooltip: 'Edit reminder',
      ),
    );
  }
}
