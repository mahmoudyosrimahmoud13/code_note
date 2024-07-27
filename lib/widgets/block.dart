import 'package:flutter/material.dart';

class Block extends StatelessWidget {
  const Block({super.key, required this.id, this.onPressed});
  final String id;
  final void Function(String vlaue)? onPressed;

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
