import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../../features/notes/presentation/pages/image_preview_page.dart';
import '../../helpers/helper_methods.dart';
import 'block.dart';
import 'block_frame.dart';

/// An image block. Actions sit in the header above the picture, so they
/// never cover it.
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
    final color = Theme.of(context).colorScheme;
    final provider = widget.imageProvider;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlockHeader(
            label: 'image',
            icon: Icons.image_outlined,
            quickActions: [
              if (provider != null)
                BlockQuickAction(
                  icon: Icons.open_in_full_rounded,
                  tooltip: 'View full size',
                  onPressed: () =>
                      navigateTo(toPage: ImagePreview(image: provider)),
                ),
            ],
            onMoveUp: widget.moveUp == null ? null : () => widget.moveUp!(widget.id),
            onMoveDown:
                widget.moveDown == null ? null : () => widget.moveDown!(widget.id),
            onDelete: widget.delete == null ? null : () => widget.delete!(widget.id),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppBrand.radius),
            child: provider == null
                ? Container(
                    height: 160,
                    color: color.surfaceContainer,
                    child: Icon(Icons.broken_image_outlined,
                        color: context.tokens.subtle),
                  )
                : GestureDetector(
                    onTap: () =>
                        navigateTo(toPage: ImagePreview(image: provider)),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: Image(
                        image: provider,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        semanticLabel: 'Image in note',
                        errorBuilder: (context, error, stack) => Container(
                          height: 160,
                          color: color.surfaceContainer,
                          child: Icon(Icons.broken_image_outlined,
                              color: context.tokens.subtle),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
