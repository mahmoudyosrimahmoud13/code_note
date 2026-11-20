import 'package:code_note/core/util/markdown_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('headings, bold, code and links lose their markdown marks', () {
    final lines = MarkdownPreview.parse('# Title\nSome **bold** and `code` with a [link](https://x.y).');
    expect(lines[0].heading, 1);
    expect(lines[0].plain, 'Title');
    expect(lines[1].plain, 'Some bold and code with a link.');
    expect(lines[1].segments.firstWhere((s) => s.bold).text, 'bold');
    expect(lines[1].segments.firstWhere((s) => s.code).text, 'code');
    expect(lines[1].segments.firstWhere((s) => s.link).text, 'link');
  });

  test('lists, tasks, quotes and tables read naturally', () {
    final lines = MarkdownPreview.parse('- one\n- [x] done\n- [ ] todo\n> quote\n| a | b |\n|---|---|\n| 1 | 2 |\n---');
    expect(lines.map((l) => l.plain).toList(), ['• one', '☑ done', '☐ todo', 'quote', 'a   b', '1   2']);
    expect(lines[3].quote, isTrue);
  });

  test('code fences show their code, images disappear, max lines is kept', () {
    final lines = MarkdownPreview.parse('```py\nprint(1)\n```\n![pic](a.png)\ntext');
    expect(lines.first.codeBlock, isTrue);
    expect(lines.first.plain, 'print(1)');
    expect(lines.last.plain, 'text');
    expect(MarkdownPreview.parse(List.filled(30, 'line').join('\n'), maxLines: 4), hasLength(4));
  });
}
