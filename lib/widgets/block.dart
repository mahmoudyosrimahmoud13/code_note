import 'package:flutter/material.dart';

class Block extends StatefulWidget {
  const Block(
      {super.key,
      this.image,
      required this.id,
      this.onPressed,
      this.moveUp,
      this.moveDown});
  final String id;
  final void Function(String vlaue)? onPressed;
  final void Function(String vlaue)? moveUp;
  final void Function(String vlaue)? moveDown;
  final ImageProvider? image;

  @override
  State<Block> createState() => _BlockState();
}

class _BlockState extends State<Block> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
