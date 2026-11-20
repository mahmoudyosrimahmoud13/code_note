import 'package:code_note/features/notebook/ipynb_import.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/note.dart';
import 'package:code_note/features/workspace/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV with quotes, commas and new lines inside cells', () {
    final t = DataTableData.parseDelimited('name,city,orders\n"Lee, Ann",Cairo,40\nOmar,"Giza\nwest",12\r\nSara,,7\n');
    expect(t.columns, ['name', 'city', 'orders']);
    expect(t.rows, hasLength(3));
    expect(t.rows[0], ['Lee, Ann', 'Cairo', '40']);
    expect(t.rows[1][1], 'Giza\nwest');
    expect(t.rows[2], ['Sara', '', '7']);
  });

  test('guesses ; and tab delimiters', () {
    expect(DataTableData.parseDelimited('a;b\n1;2\n').columns, ['a', 'b']);
    expect(DataTableData.parseDelimited('a\tb\n1\t2\n').rows.single, ['1', '2']);
  });

  test('JSON records and columns', () {
    final records = DataTableData.parseJson('[{"a": 1, "b": "x"}, {"a": 2, "c": true}]');
    expect(records.columns, ['a', 'b', 'c']);
    expect(records.rows[1], ['2', '', 'true']);
    final cols = DataTableData.parseJson('{"a": [1, 2], "b": ["x", "y"]}');
    expect(cols.rows, [['1', 'x'], ['2', 'y']]);
    expect(DataTableData.parseJson('{"data": [{"k": 1}]}').columns, ['k']);
  });

  test('column stats: numbers, missing values, top values', () {
    final t = DataTableData.parseDelimited('n,city\n1,Cairo\n2,Cairo\n3,\nNA,Giza\n10,Cairo\n');
    final n = ColumnStats.of(t, 0);
    expect(n.numeric, isTrue);
    expect(n.missing, 1);
    expect(n.min, 1);
    expect(n.max, 10);
    expect(n.mean, 4);
    expect(n.median, 2.5);
    expect(n.histogram.reduce((a, b) => a + b), 4);
    final city = ColumnStats.of(t, 1);
    expect(city.numeric, isFalse);
    expect(city.top.first, ('Cairo', 3));
    expect(city.missing, 1);
  });

  test('sort numbers as numbers, missing last; filter any column', () async {
    final t = DataTableData.parseDelimited('n,city\n10,Cairo\n9,Giza\n,Alex\n100,Cairo\n');
    expect(await DataQuery.run(DataQuery(t, sortColumn: 0)), [1, 0, 3, 2]);
    expect(await DataQuery.run(DataQuery(t, sortColumn: 0, descending: true)), [3, 0, 1, 2]);
    expect(await DataQuery.run(DataQuery(t, filter: 'cai')), [0, 3]);
  });

  test('.py files split into cells at # %% and back', () {
    const py = '# %% [markdown]\n# # Title\n# Some text\n\n# %%\nimport pandas as pd\n\n# %%\nprint(1)\n';
    final blocks = FileNotes.blocksFor('analysis.py', py);
    expect(blocks, hasLength(3));
    expect(blocks[0], isA<MarkdownBlockEntity>());
    expect(blocks[0].text, '# Title\nSome text');
    expect(blocks[1].text, 'import pandas as pd');
    final note = NoteEntity(id: 'n', title: 'analysis', tags: const [], lastModified: DateTime(2026), blocks: blocks);
    final back = FileNotes.textFor('analysis.py', note);
    expect(back, contains('# %% [markdown]\n# # Title\n# Some text'));
    expect(back, contains('# %%\nimport pandas as pd'));
    expect(FileNotes.blocksFor('analysis.py', back), hasLength(3));
  });

  test('notes export to .ipynb that imports back', () async {
    final note = NoteEntity(id: 'n', title: 'Sales', tags: const [], lastModified: DateTime(2026), blocks: const [
      MarkdownBlockEntity(id: '1', text: 'Some notes'),
      CodeBlockEntity(id: '2', text: 'x = 1\nx'),
    ]);
    final nb = IpynbExport.fromNote(note);
    final blocks = await IpynbImport.toBlocks(nb, saveImage: (_, __) async => '');
    expect(blocks.map((b) => b.text), ['# Sales', 'Some notes', 'x = 1\nx']);
  });
}
