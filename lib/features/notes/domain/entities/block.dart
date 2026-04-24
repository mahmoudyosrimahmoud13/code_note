import 'package:equatable/equatable.dart';
import 'language.dart';

enum BlockType { note, code, image }

abstract class BlockEntity extends Equatable {
  final String id;
  final String? text;
  final String? imagePath;
  final BlockType type;

  const BlockEntity({
    required this.id,
    this.text,
    this.imagePath,
    required this.type,
  });

  BlockEntity copyWith({
    String? id,
    String? text,
    String? imagePath,
  });

  @override
  List<Object?> get props => [id, text, imagePath, type];
}

class NoteBlockEntity extends BlockEntity {
  const NoteBlockEntity({
    required super.id,
    super.text,
  }) : super(type: BlockType.note);

  @override
  NoteBlockEntity copyWith({
    String? id,
    String? text,
    String? imagePath,
  }) {
    return NoteBlockEntity(
      id: id ?? this.id,
      text: text ?? this.text,
    );
  }
}

class CodeBlockEntity extends BlockEntity {
  final Language language;

  const CodeBlockEntity({
    required super.id,
    super.text,
    this.language = Language.python,
  }) : super(type: BlockType.code);

  @override
  CodeBlockEntity copyWith({
    String? id,
    String? text,
    String? imagePath,
    Language? language,
  }) {
    return CodeBlockEntity(
      id: id ?? this.id,
      text: text ?? this.text,
      language: language ?? this.language,
    );
  }

  @override
  List<Object?> get props => [id, text, language, type];
}

class ImageBlockEntity extends BlockEntity {
  const ImageBlockEntity({
    required super.id,
    required String super.imagePath,
  }) : super(type: BlockType.image);

  @override
  ImageBlockEntity copyWith({
    String? id,
    String? text,
    String? imagePath,
  }) {
    return ImageBlockEntity(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath!,
    );
  }
}
