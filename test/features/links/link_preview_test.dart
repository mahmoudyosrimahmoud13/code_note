import 'package:code_note/features/links/link_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkFinder', () {
    test('finds links and drops the punctuation after them', () {
      const text = 'See https://flutter.dev. Also (www.github.com/a/b), and https://x.io/q?a=1&b=2!';
      expect(LinkFinder.urls(text), [
        'https://flutter.dev',
        'https://www.github.com/a/b',
        'https://x.io/q?a=1&b=2',
      ]);
    });

    test('keeps brackets that belong to the link', () {
      const text = 'https://en.wikipedia.org/wiki/Dart_(programming_language) is it';
      expect(LinkFinder.urls(text), ['https://en.wikipedia.org/wiki/Dart_(programming_language)']);
    });

    test('ignores half links and plain words', () {
      expect(LinkFinder.urls('type https:// and www. here, email me at a@b.com'), isEmpty);
    });

    test('each link once', () {
      expect(LinkFinder.urls('https://a.com https://a.com'), ['https://a.com']);
    });

    test('ranges point at the link text', () {
      const text = 'go to www.dart.dev now';
      final r = LinkFinder.ranges(text).single;
      expect(r.textInside(text), 'www.dart.dev');
    });

    test('domain', () {
      expect(LinkFinder.domain('https://www.github.com/mahmoud'), 'github.com');
      expect(LinkFinder.domain('https://pub.dev/packages/http'), 'pub.dev');
    });
  });

  group('LinkPreview.fromHtml', () {
    test('reads Open Graph tags', () {
      const html = '''<html><head>
<title>Fallback</title>
<meta property="og:title" content="CodeNote &amp; friends">
<meta property="og:description" content='Notes that run &#39;code&#39;'>
<meta property="og:image" content="/img/card.png">
<meta property="og:site_name" content="GitHub">
</head><body></body></html>''';
      final p = LinkPreview.fromHtml('https://github.com/a/b', html);
      expect(p.title, 'CodeNote & friends');
      expect(p.description, "Notes that run 'code'");
      expect(p.image, 'https://github.com/img/card.png');
      expect(p.site, 'GitHub');
    });

    test('content before property, and twitter tags', () {
      const html = '<meta content="Hi there" name="twitter:title"><meta name=description content=Short>';
      final p = LinkPreview.fromHtml('https://x.com', html);
      expect(p.title, 'Hi there');
      expect(p.description, 'Short');
    });

    test('falls back to <title>', () {
      final p = LinkPreview.fromHtml('https://a.com', '<head><title>\n  Plain   page </title></head>');
      expect(p.title, 'Plain page');
      expect(p.image, isNull);
    });

    test('empty page has nothing', () {
      expect(LinkPreview.fromHtml('https://a.com', '<p>hello</p>').isEmpty, isTrue);
    });

    test('saved and read back', () {
      const p = LinkPreview(url: 'https://a.com', title: 'A', image: 'https://a.com/i.png');
      final back = LinkPreview.fromMap(p.toMap());
      expect(back.title, 'A');
      expect(back.image, 'https://a.com/i.png');
      expect(back.description, isNull);
    });
  });
}
