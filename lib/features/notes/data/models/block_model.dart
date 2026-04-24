import '../../domain/entities/block.dart';
import '../../domain/entities/language.dart';

class BlockModel extends BlockEntity {
  final Language? language;

  const BlockModel({
    required super.id,
    super.text,
    super.imagePath,
    required super.type,
    this.language,
  });

  factory BlockModel.fromEntity(BlockEntity entity) {
    Language? language;
    if (entity is CodeBlockEntity) {
      language = entity.language;
    }
    
    return BlockModel(
      id: entity.id,
      text: entity.text,
      imagePath: entity.imagePath,
      type: entity.type,
      language: language,
    );
  }

  factory BlockModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = BlockType.values.firstWhere((e) => e.toString() == typeStr);
    
    Language? language;
    if (json['language'] != null) {
      language = Language.values.firstWhere((e) => e.toString() == json['language']);
    }

    return BlockModel(
      id: json['id'],
      text: json['text'],
      imagePath: json['imagePath'],
      type: type,
      language: language,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'imagePath': imagePath,
      'type': type.toString(),
      'language': language?.toString(),
    };
  }

  @override
  BlockModel copyWith({
    String? id,
    String? text,
    String? imagePath,
    Language? language,
  }) {
    return BlockModel(
      id: id ?? this.id,
      text: text ?? this.text,
      imagePath: imagePath ?? this.imagePath,
      type: type,
      language: language ?? this.language,
    );
  }

  BlockEntity toEntity() {
    switch (type) {
      case BlockType.note:
        return NoteBlockEntity(id: id, text: text);
      case BlockType.code:
        return CodeBlockEntity(id: id, text: text, language: language ?? Language.dart);
      case BlockType.image:
        return ImageBlockEntity(id: id, imagePath: imagePath ?? '');
    }
  }
}
