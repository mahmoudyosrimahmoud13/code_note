import 'package:flutter/material.dart';
import 'package:widget_zoom/widget_zoom.dart';

class ImagePreview extends StatelessWidget {
  const ImagePreview({super.key, required this.image});
  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: WidgetZoom(
            heroAnimationTag: 'tag', zoomWidget: Image(image: image)),
      ),
    );
  }
}
