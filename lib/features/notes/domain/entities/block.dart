import 'package:equatable/equatable.dart';

import 'language.dart';

enum BlockType { note, code, image, markdown }

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

class MarkdownBlockEntity extends BlockEntity {
  const MarkdownBlockEntity({
    required super.id,
    super.text,
  }) : super(type: BlockType.markdown);

  @override
  MarkdownBlockEntity copyWith({
    String? id,
    String? text,
    String? imagePath,
  }) {
    return MarkdownBlockEntity(
      id: id ?? this.id,
      text: text ?? this.text,
    );
  }
}

/// How a code block takes part when its note (or folder) runs as a
/// sequence: blocks run top to bottom, each finishing before the next.
enum RunRole {
  /// Runs in order, and the next block waits until it finishes.
  normal,

  /// The primary block: always runs last and keeps running (a server).
  main,

  /// Never started by Run note or Run folder (its own ▶ still works).
  skip,

  /// Starts in order, but the next block doesn't wait for it (an extra server).
  background,
}

class CodeBlockEntity extends BlockEntity {
  final Language language;
  final RunRole runRole;

  const CodeBlockEntity({
    required super.id,
    super.text,
    this.language = Language.python,
    this.runRole = RunRole.normal,
  }) : super(type: BlockType.code);

  @override
  CodeBlockEntity copyWith({
    String? id,
    String? text,
    String? imagePath,
    Language? language,
    RunRole? runRole,
  }) {
    return CodeBlockEntity(
      id: id ?? this.id,
      text: text ?? this.text,
      language: language ?? this.language,
      runRole: runRole ?? this.runRole,
    );
  }

  @override
  List<Object?> get props => [id, text, language, type, runRole];
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
