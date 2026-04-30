import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  
  ImageProvider? get imageProvider {
    if (entity.imagePath == null || entity.imagePath!.isEmpty) return null;
    
    if (entity.imagePath!.startsWith('http')) {
      return CachedNetworkImageProvider(entity.imagePath!);
    }
    
    if (kIsWeb) {
      return NetworkImage(entity.imagePath!);
    } else {
      return FileImage(File(entity.imagePath!));
    }
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.debug}) {
    return text ?? '';
  }
}
