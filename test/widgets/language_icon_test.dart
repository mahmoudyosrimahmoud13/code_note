import 'dart:io';

import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/widgets/language_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every language with a logo has its image file', () {
    final withLogo = Language.values.where(LanguageIcon.hasLogo).toList();
    expect(withLogo.length, greaterThan(40));
    for (final lang in withLogo) {
      expect(File('assets/languages/${lang.name}.png').existsSync(), isTrue,
          reason: 'missing logo for ${lang.name}');
    }
  });
}
