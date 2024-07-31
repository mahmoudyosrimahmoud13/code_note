import 'package:flutter/material.dart';

class Block extends StatefulWidget {
  Block(
      {super.key,
      this.text,
      this.image,
      required this.id,
      required this.delete,
      required this.moveUp,
      required this.moveDown});
  final String id;
  final void Function(String vlaue)? delete;
  final void Function(String vlaue)? moveUp;
  final void Function(String vlaue)? moveDown;
  final ImageProvider? image;
  String? text;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.debug}) {
    return text!;
  }

  @override
  State<Block> createState() => _BlockState();
}

class _BlockState extends State<Block> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
