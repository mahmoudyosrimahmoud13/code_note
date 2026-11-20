import 'package:code_note/features/miniapps/mini_app_server.dart';
import 'package:code_note/features/miniapps/mini_app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the bridge goes first in <head>, so it runs before the page code', () {
    const doc = '<!DOCTYPE html><html><head><title>x</title></head><body><script>go()</script></body></html>';
    final out = MiniAppServer.injectBridge(doc, '<script>bridge()</script>');
    expect(out.indexOf('bridge()'), lessThan(out.indexOf('<title>')));
    expect(MiniAppServer.injectBridge('<p>hi</p>', '<script>b</script>'), startsWith('<script>b</script>'));
  });

  test('saved data cannot break out of the script tag', () {
    final js = MiniAppServer.bridgeScript(data: {'x': '</script><script>alert(1)</script>'}, dataUrl: '/s/data/n');
    expect(js.indexOf('</script>'), js.lastIndexOf('</script>'));
    expect(js, contains('localStorage'));
    expect(js, contains('codenote'));
  });

  test('only small maps of text are accepted', () {
    expect(MiniAppStorage.decode('{"best":"12","n":3}'), {'best': '12', 'n': '3'});
    expect(MiniAppStorage.decode('[1,2]'), isNull);
    expect(MiniAppStorage.decode('not json'), isNull);
    expect(MiniAppStorage.decode('{"a":"${'x' * (MiniAppStorage.maxBytes + 10)}"}'), isNull);
  });

  test('file types for pages', () {
    expect(MiniAppServer.contentTypeFor('a/b.mp4').mimeType, 'video/mp4');
    expect(MiniAppServer.contentTypeFor('x.json').mimeType, 'application/json');
    expect(MiniAppServer.contentTypeFor('x.bin').mimeType, 'application/octet-stream');
  });
}
