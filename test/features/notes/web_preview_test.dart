import 'package:code_note/features/notes/domain/entities/block.dart';
import 'package:code_note/features/notes/domain/entities/language.dart';
import 'package:code_note/features/notes/presentation/pages/web_preview_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combines HTML, CSS and JS blocks into one page', () {
    final doc = WebPreview.buildDocument('Demo', const [
      CodeBlockEntity(id: '1', language: Language.html, text: '<h1>Hi</h1>'),
      CodeBlockEntity(id: '2', language: Language.css, text: 'h1 { color: red; }'),
      CodeBlockEntity(id: '3', language: Language.javaScript, text: 'console.log(1);'),
    ]);
    expect(doc, contains('<h1>Hi</h1>'));
    expect(doc, contains('<style>'));
    expect(doc, contains('console.log(1);'));
    expect(doc.indexOf('<style>') < doc.indexOf('<h1>Hi</h1>'), isTrue);
  });

  test('a full HTML page gets the CSS and JS added inside it', () {
    final doc = WebPreview.buildDocument('x', const [
      CodeBlockEntity(
          id: '1',
          language: Language.html,
          text: '<html><head></head><body><p>a</p></body></html>'),
      CodeBlockEntity(id: '2', language: Language.css, text: 'p{}'),
    ]);
    expect(doc.indexOf('<style>') < doc.indexOf('</head>'), isTrue);
    expect('<html'.allMatches(doc).length, 1);
  });

  test('only offers a preview when there is web code', () {
    expect(WebPreview.canPreview(const [CodeBlockEntity(id: '1', language: Language.python, text: 'x')]), isFalse);
    expect(WebPreview.canPreview(const [CodeBlockEntity(id: '1', language: Language.css, text: 'a{}')]), isTrue);
  });
}
