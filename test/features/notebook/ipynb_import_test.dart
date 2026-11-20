import 'dart:convert';
import 'dart:typed_data';

import 'package:code_note/features/notebook/ipynb_import.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final saved = <String>[];
  Future<String> save(Uint8List bytes, String ext) async {
    saved.add(ext);
    return '/images/${saved.length}.$ext';
  }

  final notebook = jsonEncode({
    'cells': [
      {'cell_type': 'markdown', 'metadata': {}, 'source': ['# Sales\n', 'A small look at orders.']},
      {
        'cell_type': 'code',
        'execution_count': 1,
        'metadata': {},
        'source': ['import pandas as pd\n', "df = pd.read_csv('orders.csv')\n", 'df.head()'],
        'outputs': [
          {'output_type': 'stream', 'name': 'stdout', 'text': ['loaded 120 rows\n']},
          {
            'output_type': 'execute_result',
            'execution_count': 1,
            'data': {'text/plain': ['   city  orders\n', '0  Cairo  40'], 'text/html': '<table></table>'},
            'metadata': {},
          },
          {
            'output_type': 'display_data',
            'data': {'image/png': base64Encode([137, 80, 78, 71]), 'text/plain': '<Figure>'},
            'metadata': {},
          },
        ],
      },
      {
        'cell_type': 'code',
        'source': '1/0',
        'outputs': [
          {'output_type': 'error', 'ename': 'ZeroDivisionError', 'evalue': 'division by zero', 'traceback': ['\u001b[31mZeroDivisionError\u001b[0m: division by zero']},
        ],
      },
    ],
    'metadata': {
      'kernelspec': {'name': 'python3', 'language': 'python'},
      'language_info': {'name': 'python', 'file_extension': '.py'},
    },
    'nbformat': 4,
    'nbformat_minor': 5,
  });

  test('cells become blocks, outputs follow their cell', () async {
    saved.clear();
    final blocks = await IpynbImport.toBlocks(notebook, saveImage: save);

    expect(blocks.first, isA<MarkdownBlockEntity>());
    expect(blocks.first.text, '# Sales\nA small look at orders.');

    final code = blocks[1] as CodeBlockEntity;
    expect(code.language, Language.python);
    expect(code.text, "import pandas as pd\ndf = pd.read_csv('orders.csv')\ndf.head()");

    // stdout and the table's text join into one output block, then the plot.
    expect(blocks[2].text, contains('loaded 120 rows'));
    expect(blocks[2].text, contains('Cairo'));
    expect(blocks[3], isA<ImageBlockEntity>());
    expect(blocks[3].imagePath, '/images/1.png');
    expect(saved, ['png']);

    expect(blocks[4], isA<CodeBlockEntity>());
    expect(blocks[5].text, contains('ZeroDivisionError: division by zero'));
    expect(blocks[5].text, isNot(contains('\u001b')));
    expect(blocks, hasLength(6));
  });

  test('R notebooks get R code blocks', () async {
    final r = jsonEncode({
      'cells': [
        {'cell_type': 'code', 'source': 'summary(cars)', 'outputs': []},
      ],
      'metadata': {'kernelspec': {'language': 'R'}, 'language_info': {'name': 'R'}},
      'nbformat': 4,
      'nbformat_minor': 5,
    });
    final blocks = await IpynbImport.toBlocks(r, saveImage: save);
    expect((blocks.single as CodeBlockEntity).language, Language.r);
  });

  test('spots notebooks by their start', () {
    expect(IpynbImport.looksLikeNotebook(notebook.substring(0, 200)), isTrue);
    expect(IpynbImport.looksLikeNotebook('{"format":"codenote-backup"}'), isFalse);
  });

  test('not a notebook is an error', () async {
    expect(() => IpynbImport.toBlocks('[1, 2]', saveImage: save), throwsFormatException);
  });
}
