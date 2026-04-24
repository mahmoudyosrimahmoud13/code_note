import 'dart:io';
import '../../domain/entities/block.dart';
import '../../../../widgets/custom_button.dart';
import '../../../../widgets/custom_icon_button.dart';
import '../../../../helpers/helper_methods.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image_picker/image_picker.dart';

class ScanDocument extends StatefulWidget {
  const ScanDocument({
    super.key,
    required this.onPressed,
    this.moveUp,
    this.moveDown,
  });
  final void Function(String vlaue) onPressed;
  final void Function(String vlaue)? moveUp;
  final void Function(String vlaue)? moveDown;

  @override
  State<ScanDocument> createState() => _ScanDocumentState();
}

class _ScanDocumentState extends State<ScanDocument> {
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
    if (_pickedImage == null) return;
    
    // Check for Windows to avoid crash if google_ml_kit doesn't support it
    if (Platform.isWindows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text recognition is not supported on Windows.')),
      );
      return;
    }

    try {
      InputImage image = InputImage.fromFile(_pickedImage!);
      TextRecognizer textRecognizer = TextRecognizer();
      final textRecognized = await textRecognizer.processImage(image);
      if (!mounted) return;
      setState(() {
        _controller.text = textRecognized.text;
      });
      await textRecognizer.close();
    } catch (e) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _return(BlockEntity block) {
    Navigator.pop(context, block);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Scan'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                margin: const EdgeInsets.all(20),
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
                          const Icon(Icons.image),
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
            const SizedBox(
              height: 10,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  label: const Text('Extracted text'),
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
            const SizedBox(
              height: 10,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomIconButton(
                  icon: Icons.code,
                  onPressed: () => _return(CodeBlockEntity(
                    id: uuid.generate(),
                    text: _controller.text,
                  )),
                ),
                CustomIconButton(
                  icon: Icons.text_format,
                  onPressed: () => _return(NoteBlockEntity(
                    id: uuid.generate(),
                    text: _controller.text,
                  )),
                )
              ],
            ),
            const SizedBox(
              height: 40,
            )
          ],
        ),
      ),
    );
  }
}
