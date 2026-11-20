import 'dart:convert';
import 'dart:io';

import 'package:code_note/features/runner/python_kernel.dart';
import 'package:code_note/features/runner/rich_output_view.dart';
import 'package:code_note/features/runner/run_manager.dart';
import 'package:code_note/features/runner/runtimes.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> split(List<String> chunks, {String prefix = ''}) => RunningProcess.splitLines(
      Stream.fromIterable([for (final c in chunks) utf8.encode(c)]),
      prefix: prefix,
    ).toList();

void main() {
  test('progress bars that redraw with \\r replace their own line (tqdm)', () async {
    // The exact pattern tqdm writes, split across chunks like a pipe would.
    final lines = await split(['\rtraining:   0%| 0/5', ' [00:00]\rtraining:  40%|██', '  | 2/5\rtraining: 100%| 5/5\n', 'after\n']);
    expect(lines.where((l) => !l.startsWith(RunningProcess.replaceMark)).toList(), ['training: 100%| 5/5', 'after']);
    expect(lines.first, '${RunningProcess.replaceMark}training:   0%| 0/5 [00:00]');
  });

  test('windows line endings are ordinary new lines', () async {
    expect(await split(['one\r\ntwo\r\n']), ['one', 'two']);
  });

  test('stderr lines keep their error mark', () async {
    final lines = await split(['oops\n'], prefix: RunningProcess.errorMark);
    expect(RunningProcess.isError(lines.single), isTrue);
    expect(RunningProcess.plain(lines.single), 'oops');
  });

  test('rich output lines are read, ordinary lines are not', () {
    final r = RichOutput.parse('${outputMark}table:/tmp/x.json|3 rows × 2 columns')!;
    expect(r.kind, 'table');
    expect(r.path, '/tmp/x.json');
    expect(r.note, '3 rows × 2 columns');
    expect(RichOutput.parse('${outputMark}image:/tmp/a.png')!.path, '/tmp/a.png');
    expect(RichOutput.parse('${outputMark}count:3'), isNull);
    expect(RichOutput.parse('just text'), isNull);
  });

  test('pandas tables turn into Markdown tables', () {
    final f = File('${Directory.systemTemp.path}/codenote_table_test.json')
      ..writeAsStringSync(json.encode({
        'columns': ['qty', 'name'],
        'index': ['0', '1'],
        'data': [
          [1, 'a|b'],
          [2.5, null],
        ],
        'shape': '2 rows × 2 columns',
        'truncated': false,
      }));
    final t = OutputTable.read(f.path)!;
    final md = t.toMarkdown();
    expect(md, contains('| | qty | name |'));
    expect(md, contains(r'a\|b'));
    expect(md, contains('NaN'));
    expect(md, contains('2 rows × 2 columns'));
    f.deleteSync();
  });
}
