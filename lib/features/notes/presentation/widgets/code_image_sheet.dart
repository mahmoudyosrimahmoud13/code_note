import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import '../../../../constants/themes.dart';
import '../../../../core/util/code_languages.dart';
import '../../../../core/util/note_share_helper.dart';
import '../../domain/entities/language.dart';

/// "Share as image": a code block drawn as a clean picture for social posts.
Future<void> showCodeImageSheet(
  BuildContext context, {
  required String code,
  required Language language,
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CodeImageSheet(code: code, language: language, title: title),
  );
}

class _Background {
  const _Background(this.name, this.decoration, this.syntax, this.window, this.dark);
  final String name;
  final BoxDecoration decoration;
  final Map<String, TextStyle> syntax;
  final Color window;
  final bool dark;
}

final _backgrounds = <_Background>[
  const _Background(
    'CodeNote',
    BoxDecoration(gradient: AppBrand.gradient),
    atomOneDarkTheme,
    Color(0xF20B0C1A),
    true,
  ),
  const _Background(
    'Midnight',
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
      ),
    ),
    monokaiSublimeTheme,
    Color(0xF2111417),
    true,
  ),
  const _Background(
    'Sunset',
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF9A8B), Color(0xFFFF6A88), Color(0xFFFF99AC)],
      ),
    ),
    atomOneDarkTheme,
    Color(0xF21E1E2A),
    true,
  ),
  const _Background(
    'Paper',
    BoxDecoration(color: Color(0xFFEDEBF7)),
    githubTheme,
    Color(0xFFFFFFFF),
    false,
  ),
  const _Background(
    'Light',
    BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFA1C4FD), Color(0xFFC2E9FB)]),
    ),
    atomOneLightTheme,
    Color(0xFFFFFFFF),
    false,
  ),
];

class _CodeImageSheet extends StatefulWidget {
  const _CodeImageSheet({required this.code, required this.language, this.title});
  final String code;
  final Language language;
  final String? title;

  @override
  State<_CodeImageSheet> createState() => _CodeImageSheetState();
}

class _CodeImageSheetState extends State<_CodeImageSheet> {
  final GlobalKey _shotKey = GlobalKey();
  int _bg = 0;
  bool _busy = false;

  String get _fileTitle {
    final info = languageInfo(widget.language);
    final t = (widget.title ?? '').trim();
    if (t.isNotEmpty) return t;
    return info.extension == 'Dockerfile' ? 'Dockerfile' : 'snippet.${info.extension}';
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('empty image');
      final name = _fileTitle.replaceAll(RegExp(r'[^\w.-]+'), '_');
      final saved = await NoteShareHelper.saveOrShareBytes(
        data.buffer.asUint8List(),
        fileName: '$name.png',
        mimeType: 'image/png',
        typeLabel: 'PNG image',
        shareText: 'Made with CodeNote',
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved $saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Couldn't make the image: $e")));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final bg = _backgrounds[_bg];
    final info = languageInfo(widget.language);
    // Long snippets make unreadable images, so cap at 40 lines.
    final lines = widget.code.trimRight().split('\n');
    final code = lines.length > 40
        ? '${lines.take(40).join('\n')}\n…'
        : lines.join('\n');

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Share as image',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _shotKey,
                      child: Container(
                        decoration: bg.decoration,
                        padding: const EdgeInsets.all(48),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 420, maxWidth: 760),
                          child: Container(
                            decoration: BoxDecoration(
                              color: bg.window,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55000000),
                                  blurRadius: 30,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                                  child: Row(children: [
                                    for (final c in const [
                                      Color(0xFFFF5F57),
                                      Color(0xFFFEBC2E),
                                      Color(0xFF28C840),
                                    ])
                                      Container(
                                        width: 12,
                                        height: 12,
                                        margin: const EdgeInsets.only(right: 7),
                                        decoration: BoxDecoration(
                                            color: c, shape: BoxShape.circle),
                                      ),
                                    const SizedBox(width: 8),
                                    Text(_fileTitle,
                                        style: TextStyle(
                                          fontFamily: AppBrand.mono,
                                          fontSize: 12,
                                          color: bg.dark
                                              ? const Color(0x99FFFFFF)
                                              : const Color(0x99000000),
                                        )),
                                  ]),
                                ),
                                HighlightView(
                                  code,
                                  language: info.highlightId,
                                  theme: {
                                    ...bg.syntax,
                                    'root': (bg.syntax['root'] ?? const TextStyle())
                                        .copyWith(backgroundColor: Colors.transparent),
                                  },
                                  padding: const EdgeInsets.fromLTRB(20, 10, 24, 22),
                                  textStyle: const TextStyle(
                                    fontFamily: AppBrand.mono,
                                    fontSize: 15,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (var i = 0; i < _backgrounds.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_backgrounds[i].name),
                        selected: _bg == i,
                        onSelected: (_) => setState(() => _bg = i),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share_rounded),
                  label: const Text('Save or share image'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
