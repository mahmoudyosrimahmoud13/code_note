import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../domain/entities/block.dart';
import '../../domain/entities/language.dart';
import '../../domain/entities/note.dart';
import '../../../miniapps/mini_app_server.dart';

/// Live preview for notes with HTML, CSS and JavaScript blocks.
class WebPreview {
  WebPreview._();

  static const _web = {Language.html, Language.css, Language.javaScript};

  /// True when [blocks] has something to preview.
  static bool canPreview(List<BlockEntity> blocks) => blocks.any((b) =>
      b is CodeBlockEntity && _web.contains(b.language) && (b.text ?? '').trim().isNotEmpty);

  /// Builds one page from all the HTML, CSS and JS blocks, in note order.
  static String buildDocument(String title, List<BlockEntity> blocks) {
    final code = blocks.whereType<CodeBlockEntity>();
    String join(Language l) => code
        .where((b) => b.language == l)
        .map((b) => (b.text ?? '').trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    final html = join(Language.html);
    final css = join(Language.css);
    final js = join(Language.javaScript);
    final style = css.isEmpty ? '' : '<style>\n$css\n</style>';
    final script = js.isEmpty ? '' : '<script>\n$js\n</script>';

    // A full page written by the person: add CSS and JS into it.
    if (html.toLowerCase().contains('<html')) {
      var doc = html;
      doc = doc.contains('</head>') ? doc.replaceFirst('</head>', '$style\n</head>') : '$style\n$doc';
      doc = doc.contains('</body>') ? doc.replaceFirst('</body>', '$script\n</body>') : '$doc\n$script';
      return doc;
    }
    final safeTitle = title.replaceAll('<', '&lt;');
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$safeTitle</title>
$style
</head>
<body>
$html
$script
</body>
</html>''';
  }

  /// Runs the note: inside the app on phones, in the browser on desktop.
  /// Pages can save data with localStorage or codenote.storage; it's kept
  /// per note by CodeNote.
  static Future<void> open(BuildContext context, NoteEntity note, {String? spaceKey}) async {
    final doc = buildDocument(note.title.isEmpty ? 'Preview' : note.title, note.blocks);
    final messenger = ScaffoldMessenger.of(context);
    final url = kIsWeb ? null : await MiniAppServer.instance.serve(note.id, doc, spaceKey: spaceKey);
    if (!context.mounted) return;
    if (url == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Running without saving: CodeNote couldn't start its local page server."),
        persist: false,
      ));
    }
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _WebPreviewPage(
                title: note.title,
                url: url,
                html: MiniAppServer.injectBridge(doc, MiniAppServer.bridgeScript(data: const {})))),
      );
      return;
    }
    Uri target;
    if (url != null) {
      target = url;
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/codenote-preview.html');
      await file.writeAsString(
          MiniAppServer.injectBridge(doc, MiniAppServer.bridgeScript(data: const {})),
          flush: true);
      target = Uri.file(file.path);
    }
    final ok = await launchUrl(target);
    if (!ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open a browser for the preview."), persist: false));
    }
  }
}

class _WebPreviewPage extends StatefulWidget {
  const _WebPreviewPage({required this.title, required this.url, required this.html});
  final String title;

  /// The page on CodeNote's local server, so it can save data.
  final Uri? url;

  /// Fallback when the server isn't available.
  final String html;

  @override
  State<_WebPreviewPage> createState() => _WebPreviewPageState();
}

class _WebPreviewPageState extends State<_WebPreviewPage> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final url = widget.url;
    if (url != null) {
      _controller.loadRequest(url);
    } else {
      _controller.loadHtmlString(widget.html);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.isEmpty ? 'Preview' : widget.title),
        actions: [
          IconButton(
            tooltip: 'Run again',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(top: false, child: WebViewWidget(controller: _controller)),
    );
  }
}
