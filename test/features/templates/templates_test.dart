import 'package:code_note/features/templates/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every built-in template makes a note with fresh ids', () {
    expect(Templates.builtIn, isNotEmpty);
    for (final t in Templates.builtIn) {
      final a = t.newNote();
      final b = t.newNote();
      expect(a.id, isNot(b.id));
      expect(a.blocks.length, t.blocks.length);
      for (var i = 0; i < a.blocks.length; i++) {
        expect(a.blocks[i].id, isNot(t.blocks[i].id));
        expect(a.blocks[i].runtimeType, t.blocks[i].runtimeType);
      }
      expect(a.title.contains('{date}'), isFalse);
    }
  });

  test('template ids are unique', () {
    final ids = Templates.builtIn.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
