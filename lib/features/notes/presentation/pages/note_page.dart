import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:code_note/widgets/animated_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/block.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../bloc/note_group_bloc.dart';
import '../bloc/note_group_event.dart';
import '../bloc/note_group_state.dart';
import '../widgets/block_widget_factory.dart';
import '../../../../widgets/note_navigation_bar.dart';
import '../../../../helpers/helper_methods.dart';
import 'scan_document_page.dart';
import '../../../../core/util/note_share_helper.dart';
import '../../../../core/services/notification_service.dart';

class NotePage extends StatefulWidget {
  final NoteEntity note;

  const NotePage({super.key, required this.note});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  late final TextEditingController _titleController;
  final TextEditingController _tagController = TextEditingController();
  late List<BlockEntity> _blocks;
  late List<String> _tags;
  late DateTime _lastModified;
  late bool _isPinned;
  late bool _isArchived;
  NoteReminderEntity? _reminder;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _blocks = List.from(widget.note.blocks);
    _tags = List.from(widget.note.tags);
    _lastModified = widget.note.lastModified;
    _isPinned = widget.note.isPinned;
    _isArchived = widget.note.isArchived;
    _reminder = widget.note.reminder;
  }

  void _showReminderDialog() async {
    final color = Theme.of(context).colorScheme;
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _reminder?.dateTime ?? DateTime.now().add(const Duration(minutes: 5)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: color.copyWith(primary: color.primary),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null) return;

    if (!mounted) return;
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminder?.dateTime ?? DateTime.now().add(const Duration(minutes: 5))),
    );

    if (pickedTime == null) return;

    final reminderDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (reminderDateTime.isBefore(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder must be in the future')),
      );
      return;
    }

    final messageController = TextEditingController(text: _reminder?.message);
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reminder Message'),
        content: TextField(
          controller: messageController,
          decoration: const InputDecoration(hintText: 'Enter reminder message...'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _reminder = null;
              });
              _saveNote();
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final granted = await NotificationService().requestPermission();
              if (!granted) {
                // We might want to show a message, but on some platforms it's not needed
              }
              setState(() {
                _reminder = NoteReminderEntity(
                  dateTime: reminderDateTime,
                  message: messageController.text,
                );
              });
              _saveNote();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _addNoteBlock() {
    setState(() {
      _blocks.add(NoteBlockEntity(id: uuid.generate()));
    });
    _saveNote();
  }

  void _addCodeBlock() {
    setState(() {
      _blocks.add(CodeBlockEntity(id: uuid.generate()));
    });
    _saveNote();
  }

  void _addImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _blocks.add(ImageBlockEntity(id: uuid.generate(), imagePath: image.path));
      });
      _saveNote();
    }
  }

  void _scanDoc() async {
     final result = await Navigator.of(context).push(MaterialPageRoute<BlockEntity>(
      builder: (context) => ScanDocument(
        onPressed: _deleteBlock,
        moveDown: _moveDown,
        moveUp: _moveUp,
      ),
    ));
    if (result != null) {
      setState(() {
        _blocks.add(result);
      });
      _saveNote();
    }
  }

  void _deleteBlock(String id) {
    setState(() {
      _blocks.removeWhere((b) => b.id == id);
    });
    _saveNote();
  }

  void _moveUp(String id) {
    final index = _blocks.indexWhere((b) => b.id == id);
    if (index > 0) {
      setState(() {
        final temp = _blocks[index - 1];
        _blocks[index - 1] = _blocks[index];
        _blocks[index] = temp;
      });
      _saveNote();
    }
  }

  void _moveDown(String id) {
    final index = _blocks.indexWhere((b) => b.id == id);
    if (index < _blocks.length - 1) {
      setState(() {
        final temp = _blocks[index + 1];
        _blocks[index + 1] = _blocks[index];
        _blocks[index] = temp;
      });
      _saveNote();
    }
  }

  void _onBlockChanged(BlockEntity updatedBlock) {
    final index = _blocks.indexWhere((b) => b.id == updatedBlock.id);
    if (index != -1) {
      setState(() {
        _blocks[index] = updatedBlock;
      });
      _saveNote(); // Auto-save on every change
    }
  }

  void _saveNote() {
    if (!mounted) return;
    
    // Only save if there's actually something to save
    if (_titleController.text.isEmpty && _blocks.isEmpty && _tags.isEmpty && _reminder == null) return;

    final updatedNote = NoteEntity(
      id: widget.note.id,
      title: _titleController.text,
      tags: _tags,
      lastModified: DateTime.now(),
      blocks: _blocks,
      isPinned: _isPinned,
      isArchived: _isArchived,
      reminder: _reminder,
    );
    context.read<NoteBloc>().add(UpdateNoteEvent(updatedNote));
    
    // Handle notification
    final notificationService = NotificationService();
    final notificationId = widget.note.id.hashCode;
    
    if (_reminder != null) {
      notificationService.scheduleNotification(
        id: notificationId,
        title: _titleController.text.isEmpty ? 'Note Reminder' : _titleController.text,
        body: _reminder!.message.isEmpty ? 'Tap to view note' : _reminder!.message,
        scheduledDate: _reminder!.dateTime,
      );
    } else {
      notificationService.cancelNotification(notificationId);
    }

    setState(() {
      _lastModified = updatedNote.lastModified;
    });
  }

  void _shareNote() {
    final note = NoteEntity(
      id: widget.note.id,
      title: _titleController.text,
      tags: _tags,
      lastModified: _lastModified,
      blocks: _blocks,
    );

    final languages = _blocks
        .whereType<CodeBlockEntity>()
        .map((e) => e.language)
        .toSet()
        .toList();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share Note', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy to Clipboard'),
                onTap: () {
                  NoteShareHelper.copyToClipboard(NoteShareHelper.formatNoteAsText(note));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Share as .txt'),
                onTap: () {
                  NoteShareHelper.shareAsTxt(note);
                  Navigator.pop(context);
                },
              ),
              if (languages.isNotEmpty) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Share as Source Code'),
                ),
                ...languages.map((lang) => ListTile(
                  leading: const Icon(Icons.code),
                  title: Text('Share as ${lang.name.toUpperCase()} file'),
                  onTap: () {
                    NoteShareHelper.shareNoteAsFile(note, lang);
                    Navigator.pop(context);
                  },
                )),
              ],
            ],
          ),
        );
      },
    );
  }

  void _addTag(String tag) {
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
      _saveNote();
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    _saveNote();
  }

  void _addToGroup() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return BlocBuilder<NoteGroupBloc, NoteGroupState>(
          builder: (context, state) {
            if (state is NoteGroupLoaded) {
              if (state.groups.isEmpty) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text('No groups yet. Create one on the Home screen.'),
                ));
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Add to Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const Divider(),
                  ...state.groups.map((group) {
                    final isInGroup = group.noteIds.contains(widget.note.id);
                    return ListTile(
                      leading: Icon(isInGroup ? Icons.folder : Icons.folder_outlined),
                      title: Text(group.name),
                      trailing: isInGroup ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () {
                        List<String> newNoteIds = List.from(group.noteIds);
                        if (isInGroup) {
                          newNoteIds.remove(widget.note.id);
                        } else {
                          newNoteIds.add(widget.note.id);
                        }
                        context.read<NoteGroupBloc>().add(UpdateGroupEvent(
                          group.copyWith(noteIds: newNoteIds),
                        ));
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(
              _reminder != null ? Icons.notifications_active : Icons.notifications_none,
              color: _reminder != null ? color.primary : null,
            ),
            tooltip: 'Reminder',
            onPressed: _showReminderDialog,
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Add to Group',
            onPressed: _addToGroup,
          ),
          IconButton(
            icon: BouncyIcon(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                  key: ValueKey(_isPinned),
                  color: _isPinned ? Colors.amber : null,
                ),
              ),
            ),
            tooltip: 'Pin Note',
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _isPinned = !_isPinned;
              });
              _saveNote();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archive') {
                setState(() {
                  _isArchived = !_isArchived;
                });
                _saveNote();
                if (_isArchived) Navigator.pop(context);
              } else if (value == 'share') {
                _shareNote();
              } else if (value == 'delete') {
                context.read<NoteBloc>().add(UpdateNoteEvent(widget.note.copyWith(isDeleted: true)));
                Navigator.pop(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: BouncyIcon(
                    child: Icon(_isArchived ? Icons.unarchive_rounded : Icons.archive_rounded),
                  ),
                  title: Text(_isArchived ? 'Dearchive' : 'Archive'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: const BouncyIcon(child: Icon(Icons.share_rounded)),
                  title: const Text('Share'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const BouncyIcon(child: Icon(Icons.delete_outline_rounded, color: Colors.red)),
                  title: const Text('Delete', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last modified: ${DateFormat.yMMMd().add_jm().format(_lastModified)}',
                          style: textTheme.labelSmall!.copyWith(color: color.outline),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _titleController,
                          style: textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'Note Title',
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => _saveNote(),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ..._tags.map((tag) => Chip(
                              label: Text(tag, style: const TextStyle(fontSize: 12)),
                              onDeleted: () => _removeTag(tag),
                              deleteIconColor: color.error,
                              backgroundColor: color.secondaryContainer.withAlpha(150),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            )),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _tagController,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: '+ Add tag',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: _addTag,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _blocks.length,
                          itemBuilder: (context, index) {
                            final block = _blocks[index];
                            return BlockWidgetFactory.createBlockWidget(
                              entity: block,
                              onChanged: _onBlockChanged,
                              onDelete: _deleteBlock,
                              onMoveUp: _moveUp,
                              onMoveDown: _moveDown,
                            );
                          },
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NoteNavigationBar(
        addText: _addNoteBlock,
        addCode: _addCodeBlock,
        addImage: _addImage,
        scanDoc: _scanDoc,
      ),
    );
  }
}
