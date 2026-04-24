import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gallery_image_viewer/gallery_image_viewer.dart';
import '../../domain/entities/note.dart';
import '../../domain/entities/block.dart';
import '../bloc/note_bloc.dart';
import '../bloc/note_event.dart';
import '../widgets/block_widget_factory.dart';
import '../../../../widgets/note_navigation_bar.dart';
import '../../../../widgets/custom_icon_button.dart';
import '../../../../helpers/helper_methods.dart';
import 'scan_document_page.dart';

class NotePage extends StatefulWidget {
  final NoteEntity note;

  const NotePage({super.key, required this.note});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  late final TextEditingController _titleController;
  late List<BlockEntity> _blocks;
  late DateTime _lastModified;
  late bool _isPinned;
  late bool _isArchived;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _blocks = List.from(widget.note.blocks);
    _lastModified = widget.note.lastModified;
    _isPinned = widget.note.isPinned;
    _isArchived = widget.note.isArchived;
  }

  void _addNoteBlock() {
    setState(() {
      _blocks.add(NoteBlockEntity(id: uuid.generate()));
    });
  }

  void _addCodeBlock() {
    setState(() {
      _blocks.add(CodeBlockEntity(id: uuid.generate()));
    });
  }

  void _addImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _blocks.add(ImageBlockEntity(id: uuid.generate(), imagePath: image.path));
      });
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
    }
  }

  void _deleteBlock(String id) {
    setState(() {
      _blocks.removeWhere((b) => b.id == id);
    });
  }

  void _moveUp(String id) {
    final index = _blocks.indexWhere((b) => b.id == id);
    if (index > 0) {
      setState(() {
        final temp = _blocks[index - 1];
        _blocks[index - 1] = _blocks[index];
        _blocks[index] = temp;
      });
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
    if (_titleController.text.isEmpty && _blocks.isEmpty) return;

    final updatedNote = NoteEntity(
      id: widget.note.id,
      title: _titleController.text,
      tags: widget.note.tags,
      lastModified: DateTime.now(),
      blocks: _blocks,
      isPinned: _isPinned,
      isArchived: _isArchived,
    );
    context.read<NoteBloc>().add(UpdateNoteEvent(updatedNote));
  }

  @override
  void dispose() {
    _titleController.dispose();
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
              _isPinned ? Icons.star : Icons.star_border,
              color: _isPinned ? Colors.amber : null,
            ),
            onPressed: () {
              setState(() {
                _isPinned = !_isPinned;
              });
              _saveNote();
            },
          ),
          IconButton(
            icon: Icon(_isArchived ? Icons.unarchive : Icons.archive),
            onPressed: () {
              setState(() {
                _isArchived = !_isArchived;
              });
              _saveNote();
              // If archived, we usually want to go back to home
              if (_isArchived) Navigator.pop(context);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              context.read<NoteBloc>().add(DeleteNoteEvent(widget.note.id));
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _titleController,
                  onChanged: (_) => _saveNote(), // Optional: save on every title change
                  decoration: InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    hintStyle: textTheme.headlineLarge!.copyWith(color: color.onSurface),
                  ),
                  style: textTheme.headlineLarge!.copyWith(color: color.onSurface),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    '${DateFormat.yMMMd().format(_lastModified)} - Last Modified',
                    style: textTheme.bodyMedium!.copyWith(color: color.secondary),
                  ),
                ),
                ..._blocks.map((entity) => BlockWidgetFactory.createBlockWidget(
                  entity: entity,
                  onDelete: _deleteBlock,
                  onMoveUp: _moveUp,
                  onMoveDown: _moveDown,
                  onChanged: _onBlockChanged,
                )),
                const SizedBox(height: 100)
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: NoteNavigationBar(
        addText: _addNoteBlock,
        addCode: _addCodeBlock,
        addImage: _addImage,
        scanDoc: _scanDoc,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
