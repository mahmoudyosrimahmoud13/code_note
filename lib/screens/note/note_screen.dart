import 'dart:io';

import 'package:code_note/cubit/note/note_cubit.dart';
import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/models/note_model.dart';
import 'package:code_note/screens/note/Scan_document.dart';
import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/block/code_block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/block/image_block.dart';

import 'package:code_note/widgets/note_navigation_bar.dart';
import 'package:code_note/widgets/block/note_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gallery_image_viewer/gallery_image_viewer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

@immutable
class NoteScreen extends StatefulWidget {
  NoteScreen({super.key, required this.note});
  Note note;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final _titleController = TextEditingController();
  final Language language = Language.python;

  void _addCodeBlock() {
    final key = uuid.generate();

    setState(() {
      widget.note.blocks!.add(CodeBlock(
        id: key,
        delete: _deleteBlock,
        moveUp: moveUp,
        moveDown: moveDown,
        key: ValueKey(key),
        language: Language.python,
      ));
    });
  }

  void _addNoteBlock() {
    final key = uuid.generate();
    setState(() {
      widget.note.blocks!.add(NoteBlock(
        id: key,
        delete: _deleteBlock,
        moveUp: moveUp,
        moveDown: moveDown,
        key: ValueKey(key),
      ));
    });
  }

  void _addImage() async {
    ImagePicker imagePicker = ImagePicker();
    final key = uuid.generate();

    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        final imageFile = File(image.path);
        _imageProviders.add(FileImage(imageFile));
        widget.note.blocks!.add(ImageBlock(
          image: imageFile,
          id: key,
          delete: _deleteImageBlock,
          moveUp: moveUp,
          moveDown: moveDown,
          key: ValueKey(key),
        ));
      });
    }
  }

  void _deleteBlock(String id) {
    setState(() {
      widget.note.blocks!.removeWhere((element) => element.id == id);
    });
  }

  void _deleteImageBlock(String id) {
    final image = widget.note.blocks!.lastWhere((element) => element.id == id);

    setState(() {
      _imageProviders
          .removeWhere((element) => element == FileImage(image.image!));
      widget.note.blocks!.removeWhere((element) => element.id == id);
    });
  }

  void _scanDoc() async {
    Block block = await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ScanDocument(
        onPressed: _deleteBlock,
        moveDown: moveDown,
        moveUp: moveUp,
      ),
    ));
    setState(() {
      widget.note.blocks!.add(block);
    });
  }

  void moveUp(String id) {
    final index = widget.note.blocks!.indexWhere((element) => element.id == id);
    if (index == 0) {
      return;
    }

    final temp = widget.note.blocks![index - 1];
    widget.note.blocks![index - 1] = widget.note.blocks![index];
    widget.note.blocks![index] = temp;
    setState(() {});
  }

  void moveDown(String id) {
    final index = widget.note.blocks!.indexWhere((element) => element.id == id);
    if (index == widget.note.blocks!.length - 1) {
      return;
    }

    final temp = widget.note.blocks![index + 1];
    widget.note.blocks![index + 1] = widget.note.blocks![index];
    widget.note.blocks![index] = temp;
    setState(() {});
  }

  @override
  void initState() {
    if (widget.note.title != null) {
      _titleController.text = widget.note.title!;
    }
    super.initState();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    widget.note.lastModified = DateTime.now();
    widget.note.title = _titleController.text;
    if (notes.contains(widget.note)) {
      final index = notes.indexOf(widget.note);
      notes[index] = widget.note;
    } else {
      notes.add(widget.note);
    }
    BlocProvider.of<NoteCubit>(context).initializeNote(notes: []);

    super.dispose();
  }

  final List<ImageProvider> _imageProviders = [];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          CustomIconButton(
            icon: Icons.archive,
            iconSize: 15,
            onPressed: () {},
          ),
          CustomIconButton(
            icon: Icons.star,
            iconColor: Colors.amber,
            iconSize: 15,
            onPressed: () {},
          ),
          CustomIconButton(
            icon: Icons.workspaces,
            iconColor: color.onSecondary,
            borderColor: color.surface,
            innerColor: color.primary,
            iconSize: 15,
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
          child: SingleChildScrollView(
        child: Column(
          children: [
            _imageProviders.isNotEmpty
                ? GalleryImageView(
                    width: double.infinity,
                    height: size.height * 0.3,
                    textColor: Theme.of(context).colorScheme.primary,
                    listImage: _imageProviders,
                    boxFit: BoxFit.cover,
                    galleryType: 3,
                  )
                : const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                      hintStyle:
                          text.headlineLarge!.copyWith(color: color.onSurface),
                    ),
                    style: text.headlineLarge!.copyWith(color: color.onSurface),
                    minLines: 1,
                    maxLines: 1000,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '${DateFormat.yMMMd().format(widget.note.lastModified)}- Last Modified',
                      style: text.bodyMedium!.copyWith(color: color.secondary),
                    ),
                  ),
                  ...widget.note.blocks!,
                  const SizedBox(
                    height: 100,
                  )
                ],
              ),
            )
          ],
        ),
      )),
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
