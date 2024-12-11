import 'package:code_note/helpers/helper_methods.dart';
import 'package:code_note/screens/note/image_preview.dart';
import 'package:code_note/widgets/block/block.dart';
import 'package:code_note/widgets/custom_icon_button.dart';
import 'package:flutter/material.dart';

class ImageBlock extends Block {
  ImageBlock({
    required super.image,
    super.key,
    required super.id,
    super.moveUp,
    super.moveDown,
    super.delete,
  });

  @override
  State<ImageBlock> createState() => _ImageBlockState();
}

class _ImageBlockState extends State<ImageBlock> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final text = Theme.of(context).textTheme;
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () =>
          navigateTo(toPage: ImagePreview(image: FileImage(widget.image!))),
      child: Stack(
        children: [
          Container(
            margin: EdgeInsets.symmetric(vertical: 5),
            height: size.height * 0.3,
            width: double.infinity,
            decoration: BoxDecoration(
                image: DecorationImage(
                    image: FileImage(widget.image!), fit: BoxFit.cover),
                borderRadius: BorderRadius.circular(30)),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 3, vertical: 10),
              padding: EdgeInsets.symmetric(vertical: 4),
              width: 220,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withAlpha(120),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(width: 1, color: color.onSurface)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CustomIconButton(
                    icon: Icons.delete,
                    iconSize: 15,
                    innerColor: color.onError,
                    iconColor: color.error,
                    onPressed: () {
                      widget.delete!(widget.id);
                    },
                  ),
                  CustomIconButton(
                    icon: Icons.arrow_upward,
                    iconSize: 15,
                    onPressed: () {
                      widget.moveUp!(widget.id);
                    },
                  ),
                  CustomIconButton(
                    icon: Icons.arrow_downward,
                    iconSize: 15,
                    onPressed: () {
                      widget.moveDown!(widget.id);
                    },
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
