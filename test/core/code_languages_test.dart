import 'package:code_note/core/util/code_languages.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/onboarding/demo_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every language has a name, extension and highlighter', () {
    for (final lang in Language.values) {
      final info = languages[lang];
      expect(info, isNotNull, reason: '$lang is missing from the registry');
      expect(info!.label, isNotEmpty);
      expect(info.extension, isNotEmpty);
    }
  });

  test('shared files get the right language', () {
    expect(languageForFileName('main.rs'), Language.rust);
    expect(languageForFileName('app.py'), Language.python);
    expect(languageForFileName('query.sql'), Language.sql);
    expect(languageForFileName('Dockerfile'), Language.docker);
    expect(languageForFileName('config.yml'), Language.yaml);
    expect(languageForFileName('View.swift'), Language.swift);
    expect(languageForFileName('analysis.R'), Language.r);
    expect(languageForFileName('notes.txt'), Language.none);
    expect(languageForFileName('no_extension'), Language.none);
  });

  test('menu lists every language once, plain text last', () {
    final menu = menuLanguages;
    expect(menu.toSet().length, Language.values.length);
    expect(menu.last, Language.none);
  });

  test('demo folders only point at demo notes', () {
    final demo = DemoContent.build();
    final ids = demo.notes.map((n) => n.id).toSet();
    expect(demo.notes, isNotEmpty);
    for (final group in demo.groups) {
      expect(ids.containsAll(group.noteIds), isTrue);
    }
    expect(demo.notes.where((n) => n.isPinned), isNotEmpty);
  });
}
