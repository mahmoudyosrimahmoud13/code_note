import '../../helpers/helper_methods.dart';
import '../../features/notes/presentation/pages/image_preview_page.dart';
import 'block.dart';
import '../custom_icon_button.dart';
import 'package:flutter/material.dart';

class ImageBlock extends Block {
  const ImageBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
  });

  @override
  State<ImageBlock> createState() => _ImageBlockState();
}

class _ImageBlockState extends State<ImageBlock> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: widget.imageProvider == null
          ? null
          : () => navigateTo(toPage: ImagePreview(image: widget.imageProvider!)),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            height: size.height * 0.3,
            width: double.infinity,
            decoration: BoxDecoration(
                image: widget.imageProvider != null
                    ? DecorationImage(image: widget.imageProvider!, fit: BoxFit.cover)
                    : null,
                borderRadius: BorderRadius.circular(30),
                color: Colors.grey.withAlpha(50)),
          ),
          if (widget.delete != null || widget.moveUp != null || widget.moveDown != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withAlpha(120),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(width: 1, color: color.onSurface)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.delete != null)
                      CustomIconButton(
                        icon: Icons.delete,
                        iconSize: 15,
                        innerColor: color.onError,
                        iconColor: color.error,
                        onPressed: () {
                          widget.delete!(widget.id);
                        },
                      ),
                    if (widget.moveUp != null)
                      CustomIconButton(
                        icon: Icons.arrow_upward,
                        iconSize: 15,
                        onPressed: () {
                          widget.moveUp!(widget.id);
                        },
                      ),
                    if (widget.moveDown != null)
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
