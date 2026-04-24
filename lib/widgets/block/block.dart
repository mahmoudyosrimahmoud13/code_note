import 'dart:io';
import 'package:flutter/material.dart';
import '../../features/notes/domain/entities/block.dart';

abstract class Block extends StatefulWidget {
  final BlockEntity entity;
  final void Function(String id)? delete;
  final void Function(String id)? moveUp;
  final void Function(String id)? moveDown;
  final void Function(BlockEntity entity)? onChanged;

  const Block({
    super.key,
    required this.entity,
    this.delete,
    this.moveUp,
    this.moveDown,
    this.onChanged,
  });

  String get id => entity.id;
  String? get text => entity.text;
  File? get image => entity.imagePath != null ? File(entity.imagePath!) : null;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.debug}) {
    return text ?? '';
  }
}
