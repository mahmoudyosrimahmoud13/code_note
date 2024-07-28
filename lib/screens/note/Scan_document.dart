import 'dart:io';
import 'package:code_note/widgets/note_block.dart';

import 'package:code_note/widgets/block.dart';
import 'package:code_note/widgets/code_block.dart';
import 'package:code_note/widgets/custom_button.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/v4.dart';

class ScanDocument extends StatefulWidget {
  ScanDocument({super.key, required this.onPressed});
  final void Function(String vlaue) onPressed;

  @override
  State<ScanDocument> createState() => _ScanDocumentState();
}

class _ScanDocumentState extends State<ScanDocument> {
  final _uuid = UuidV4();
  File? _pickedImage;
  final _controller = TextEditingController();
  void _pickImage() async {
    ImagePicker imagePicker = ImagePicker();

    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedImage = File(image.path);
      });
    }
  }

  Future<void> _extractText() async {
    InputImage image = InputImage.fromFile(_pickedImage!);
    TextRecognizer textRecognizer = TextRecognizer();
    final textRecognized = await textRecognizer.processImage(image);

    setState(() {
      _controller.text = textRecognized.text;
    });
  }

  void _return(Block block) {
    Navigator.pop(context, block);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Document Scan'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                margin: EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: color.secondary.withAlpha(50),
                    borderRadius: BorderRadius.circular(30)),
                alignment: Alignment.center,
                height: size.height * 0.4,
                width: double.infinity,
                child: _pickedImage == null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image),
                          Text(
                            'Choose Image',
                            style: text.headlineLarge!
                                .copyWith(color: color.onSurface),
                          )
                        ],
                      )
                    : Image(
                        image: FileImage(_pickedImage!),
                        fit: BoxFit.contain,
                        width: size.width * 0.85,
                      ),
              ),
            ),
            CustomButton(
              text: 'Extract text',
              onPressed: _pickedImage == null ? null : _extractText,
            ),
            SizedBox(
              height: 10,
            ),
            Container(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  label: Text('Extracted text'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30)),
                  hintStyle: text.bodyLarge!.copyWith(color: color.onSurface),
                ),
                style: text.bodyLarge!.copyWith(color: color.onSurface),
                minLines: 1,
                maxLines: 1000,
                keyboardType: TextInputType.multiline,
              ),
            ),
            SizedBox(
              height: 10,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomIconButton(
                  icon: Icons.code,
                  onPressed: () => _return(CodeBlock(
                    id: _uuid.generate(),
                    code: _controller.text,
                    onPressed: widget.onPressed,
                  )),
                ),
                CustomIconButton(
                  icon: Icons.text_format,
                  onPressed: () => _return(NoteBlock(
                    id: _uuid.generate(),
                    text: _controller.text,
                    onPressed: widget.onPressed,
                  )),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
