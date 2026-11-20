import 'dart:io';

import 'package:code_note/features/runner/python_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Python helpers in the app match lib/features/runner/python', () {
    for (final entry in pythonHelpers.entries) {
      final file = File('lib/features/runner/python/${entry.key}');
      expect(file.readAsStringSync(), entry.value, reason: '${entry.key} changed: regenerate python_helpers.dart');
    }
  });
}
