import 'dart:io';

import 'package:code_note/screens/note/Scan_document.dart';
import 'package:code_note/widgets/block.dart';
import 'package:code_note/widgets/code_block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:code_note/widgets/image_block.dart';

import 'package:code_note/widgets/note_navigation_bar.dart';
import 'package:code_note/widgets/note_block.dart';
import 'package:flutter/material.dart';
import 'package:gallery_image_viewer/gallery_image_viewer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/v4.dart';

class NoteScreen extends StatefulWidget {
  const NoteScreen({super.key});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  final _uuid = UuidV4();
  final List<Block> _blocks = [];
  void _addCodeBlock() {
    final key = _uuid.generate();

    setState(() {
      _blocks.add(CodeBlock(
        id: key,
        onPressed: _deleteBlock,
        moveUp: moveUp,
        moveDown: moveDown,
        key: ValueKey(key),
      ));
    });
  }

  void _addNoteBlock() {
    final key = _uuid.generate();
    setState(() {
      _blocks.add(NoteBlock(
        id: key,
        onPressed: _deleteBlock,
        moveUp: moveUp,
        moveDown: moveDown,
        key: ValueKey(key),
      ));
    });
  }

  void _addImage() async {
    ImagePicker imagePicker = ImagePicker();

    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        final imageFile = FileImage(File(image.path));
        _imageProviders.add(imageFile);
        _blocks.add(ImageBlock(
          image: imageFile,
          id: _uuid.generate(),
          onPressed: _deleteImageBlock,
          moveUp: moveUp,
          moveDown: moveDown,
        ));
      });
    }
  }

  void _deleteBlock(String id) {
    setState(() {
      _blocks.removeWhere((element) => element.id == id);
    });
  }

  void _deleteImageBlock(String id) {
    final image = _blocks.lastWhere((element) => element.id == id);

    setState(() {
      _imageProviders.removeWhere((element) => element == image.image);
      _blocks.removeWhere((element) => element.id == id);
    });
  }

  void _scanDoc() async {
    Block block = await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ScanDocument(
        onPressed: _deleteBlock,
      ),
    ));
    setState(() {
      _blocks.add(block);
    });
  }

  void moveUp(String id) {
    print('fsmdkfsd');
    final index = _blocks.indexWhere((element) => element.id == id);
    if (index == 0) {
      return;
    }

    final temp = _blocks[index - 1];
    _blocks[index - 1] = _blocks[index];
    _blocks[index] = temp;
    setState(() {});
  }

  void moveDown(String id) {
    final index = _blocks.indexWhere((element) => element.id == id);
    if (index == _blocks.length - 1) {
      return;
    }

    final temp = _blocks[index + 1];
    _blocks[index + 1] = _blocks[index];
    _blocks[index] = temp;
    setState(() {});
  }

  @override
  void initState() {
    _addNoteBlock();
    super.initState();
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
                : SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  TextField(
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
                  ),
                  ..._blocks,
                  SizedBox(
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
