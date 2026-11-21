import 'package:code_note/features/notebook/ipynb_import.dart';
import 'package:code_note/features/notebook/lesson_import.dart';
import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:flutter_test/flutter_test.dart';

// Made by inPace's Python code (spec section 1): json, zlib level 9,
// URL-safe base64 without padding.
const fromInpace = 'codenote://open/eNpdUUFOwzAQ_Ioxh6ZSmqhEXCJxgDNI3Juo3TgmMbHXVtahRVX_jp3QInGyPbM769k5c2FbidZLXnItiSzylH_xcptyr7yO8KsiTwHVgN0EXYTct-_nSgPj0NojBuyezYUVPjMdLqy3uiXme4UdZRVWeDgclr4KcTLEntiuSNk2ZQ91hW5U6BOyo5dtEun1eu6IjXe7VkE3gqkTZbo8qlPmsFtH6iibOum9d1TmuTyBcVpmwpocfktmGS9PvsJdHJayor5Jh-MzfFlYJBv6tO2SVa9W19nBoQcaeHnmqg0eTbFxIwivBOjAudEa5wP-BoNksPi2H-yRCeWVJAbYstlZ2IM0bLGX8UvKyU6jkFEYnAsKCh2EdxrymEb62_GmAVKCbsT-msr7TLOXK21sO82EKWJWS5Tzj_X2Buz_Z9qAGG7TwwKtk5hDI_jl8gMIGLeW';

void main() {
  test('reads a link made by inPace', () {
    final data = LessonImport.decodeLink(fromInpace)!;
    expect(data['codenote'], 'lesson');
    expect(data['v'], 1);
    expect(data['title'], 'Lists');
    expect((data['source'] as Map)['course'], 'python-basics');
    expect((data['task'] as Map)['id'], 'm3-practical');
  });

  test('the web fallback address carries the same lesson', () {
    final body = fromInpace.substring('codenote://open/'.length);
    final web = 'https://mahmoudyosrimahmoud13.github.io/code_note/open#$body';
    expect(LessonImport.isLink(web), isTrue);
    expect(LessonImport.decodeLink(web)!['title'], 'Lists');
  });

  test('encode and decode give the same JSON back', () {
    final payload = {'codenote': 'lesson', 'v': 1, 'title': 'دروس عربية', 'markdown': 'x\n```py\nprint(1)\n```'};
    expect(LessonImport.decodeLink(LessonImport.encodeLink(payload)), payload);
  });

  test('broken links are refused, not crashed on', () {
    expect(LessonImport.decodeLink('codenote://open/not-base64!!'), isNull);
    expect(LessonImport.decodeLink('codenote://open/'), isNull);
    expect(LessonImport.isLink('https://example.com'), isFalse);
  });

  test('a lesson becomes text and runnable code blocks', () {
    final data = LessonImport.decodeLink(fromInpace)!;
    final blocks = LessonImport.blocks(data['markdown'] as String);
    expect(blocks.first, isA<MarkdownBlockEntity>());
    expect(blocks.first.text, startsWith('# Lists'));
    final code = blocks.whereType<CodeBlockEntity>().toList();
    expect(code.map((b) => b.language), [Language.python, Language.javaScript]);
    expect(code.first.text, 'nums = [3, 1, 2]\nprint(sorted(nums))');
    final text = blocks.whereType<MarkdownBlockEntity>().map((b) => b.text).join('\n');
    // Course-relative pictures go, web pictures and plain output fences stay.
    expect(text, isNot(contains('img/lists.png')));
    expect(text, contains('https://example.com/a.png'));
    expect(text, contains('```text'));
  });

  test('unmarked fences use the lesson language', () {
    final blocks = LessonImport.blocks('Intro\n```\necho hi\n```', fallback: Language.bash);
    expect((blocks.last as CodeBlockEntity).language, Language.bash);
  });

  test('fence names: aliases and names CodeNote knows', () {
    expect(LessonImport.languageFor('py'), Language.python);
    expect(LessonImport.languageFor('TypeScript'), Language.typeScript);
    expect(LessonImport.languageFor('sh'), Language.bash);
    expect(LessonImport.languageFor('rust'), Language.rust);
    expect(LessonImport.languageFor('klingon'), isNull);
  });

  test('front matter written by inPace (JSON values)', () {
    const md = '---\ncodenote: "lesson"\nv: 1\ntitle: "Lists"\nsource: {"app":"inpace","course":"python-basics","lesson":"m3-l1"}\n---\n# Lists\nBody';
    final (meta, body) = LessonImport.frontMatter(md);
    expect(meta['title'], 'Lists');
    expect(meta['v'], 1);
    expect((meta['source'] as Map)['lesson'], 'm3-l1');
    expect(body, '# Lists\nBody');
    final (none, same) = LessonImport.frontMatter('# Just markdown');
    expect(none, isEmpty);
    expect(same, '# Just markdown');
  });

  test('.md files in a workspace open the same way', () {
    final blocks = FileNotes.blocksFor('lesson.md', '---\ntitle: "x"\n---\nText\n```python\nx = 1\n```');
    expect(blocks.map((b) => b.runtimeType), [MarkdownBlockEntity, CodeBlockEntity]);
  });
}
