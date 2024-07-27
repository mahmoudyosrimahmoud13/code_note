import 'dart:io';

import 'package:code_note/widgets/block.dart';
import 'package:code_note/widgets/code_block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';

import 'package:code_note/widgets/note_navigation_bar.dart';
import 'package:code_note/widgets/text_block.dart';
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
    setState(() {
      _blocks.add(CodeBlock(
        id: _uuid.generate(),
        onPressed: _deleteBlock,
      ));
    });
  }

  void _addTextBlock() {
    setState(() {
      _blocks.add(TextBlock(
        id: _uuid.generate(),
        onPressed: _deleteBlock,
      ));
    });
  }

  void _addImage() async {
    ImagePicker imagePicker = ImagePicker();

    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        final imageFile = File(image.path);
        _imageProviders.add(FileImage(imageFile));
      });
    }
  }

  void _deleteBlock(String id) {
    setState(() {
      _blocks.removeWhere((element) => element.id == id);
    });
  }

  @override
  void initState() {
    _addTextBlock();
    super.initState();
  }

  final List<ImageProvider> _imageProviders = [
    AssetImage('assets/background/city.jpg'),
    AssetImage('assets/background/neural.jpg'),
    AssetImage('assets/background/waves.jpg'),
    AssetImage('assets/background/b7290b051bb2ce7af0aa9a2842bb5619.jpg'),
    Image.network("https://picsum.photos/seed/picsum/200/300").image,
    Image.network("https://picsum.photos/200/300?grayscale").image,
    Image.network("https://picsum.photos/200/300").image,
    Image.network("https://picsum.photos/200/300?grayscale").image
  ];

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
        addText: _addTextBlock,
        addCode: _addCodeBlock,
        addImage: _addImage,
        scanDoc: _addImage,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
