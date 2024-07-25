import 'dart:io';

import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/screens/home/home_screen.dart';
import 'package:code_note/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImagePickingScreen extends StatefulWidget {
  const ImagePickingScreen({super.key});

  @override
  State<ImagePickingScreen> createState() => _ImagePickingScreenState();
}

class _ImagePickingScreenState extends State<ImagePickingScreen> {
  File? _pickedImage;
  void _pickImage() async {
    ImagePicker imagePicker = ImagePicker();

    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedImage = File(image.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
                top: -200,
                child: CircleAvatar(
                  radius: 300,
                )),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Pick a profile photo',
                  style: text.displaySmall!.copyWith(
                      color: color.onSurface, fontWeight: FontWeight.bold),
                ),
                SizedBox(
                  height: 40,
                ),
                Container(
                  decoration: BoxDecoration(
                    color: color.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.surface,
                        spreadRadius: 5,
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: InkWell(
                    hoverColor: Color.fromARGB(0, 5, 5, 5),
                    focusColor: Color.fromARGB(0, 5, 5, 5),
                    splashColor: Color.fromARGB(0, 5, 5, 5),
                    highlightColor: Color.fromARGB(0, 5, 5, 5),
                    onTap: () {
                      _pickImage();
                    },
                    child: CircleAvatar(
                      backgroundImage: _pickedImage != null
                          ? FileImage(_pickedImage!)
                          : AssetImage('assets/stocks/profile.jpg'),
                      radius: size.width - 250,
                    ),
                  ),
                ),
                SizedBox(
                  height: 20,
                ),
                Container(
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomButton(
                        text: 'Skip',
                        backgroundColor: color.secondary,
                        onPressed: () =>
                            navigateTo(toPage: HomeScreen(), replace: true),
                      ),
                      SizedBox(
                        width: 40,
                      ),
                      CustomButton(
                        text: 'Finish',
                        onPressed: () =>
                            navigateTo(toPage: HomeScreen(), replace: true),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
