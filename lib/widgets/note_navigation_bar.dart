import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';

class NoteNavigationBar extends StatelessWidget {
  const NoteNavigationBar({
    super.key,
    this.addText,
    this.addCode,
    this.addImage,
    this.scanDoc,
  });
  final void Function()? addText;
  final void Function()? addCode;
  final void Function()? addImage;
  final void Function()? scanDoc;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 5),
      child: Container(
          height: 60,
          width: 400,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(60)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomIconButton(
                icon: Icons.text_format,
                iconSize: 20,
                onPressed: addText,
              ),
              CustomIconButton(
                icon: Icons.code,
                iconSize: 20,
                onPressed: addCode,
              ),
              CustomIconButton(
                icon: Icons.image,
                iconSize: 20,
                onPressed: addImage,
              ),
              CustomIconButton(
                icon: Icons.document_scanner_sharp,
                iconSize: 20,
                onPressed: scanDoc,
              ),
            ],
          )),
    );
  }
}
