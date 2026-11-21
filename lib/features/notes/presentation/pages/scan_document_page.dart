import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../constants/themes.dart';
import '../../../../helpers/helper_methods.dart';
import '../../../../widgets/language_drop_down.dart';
import '../../domain/entities/block.dart';
import '../../domain/entities/language.dart';

/// Scan text or code from a photo and add it to the note as a block.
/// Pops with the new [BlockEntity], or null if the person backs out.
class ScanDocument extends StatefulWidget {
  const ScanDocument({super.key});

  /// Text recognition (Google ML Kit) only exists on Android and iOS.
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  State<ScanDocument> createState() => _ScanDocumentState();
}

enum _Stage { empty, reading, done }

class _ScanDocumentState extends State<ScanDocument> {
  final _controller = TextEditingController();
  File? _image;
  _Stage _stage = _Stage.empty;
  String? _problem;
  bool _asCode = false;
  Language _language = Language.python;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    XFile? picked;
    try {
      // A smaller photo is read faster and uses far less memory; 2400 px
      // is still plenty for small print.
      picked = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 92);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _problem = source == ImageSource.camera
          ? "CodeNote can't use the camera. Allow camera access in your phone's settings, or choose a photo from the gallery."
          : "CodeNote can't open your photos (${e.message ?? e.code}).");
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _image = File(picked!.path);
      _problem = null;
    });
    await _read();
  }

  Future<void> _read() async {
    final image = _image;
    if (image == null) return;
    if (!ScanDocument.supported) {
      setState(() => _problem = 'Reading text from photos works on Android and iOS only.');
      return;
    }
    setState(() {
      _stage = _Stage.reading;
      _problem = null;
    });
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(InputImage.fromFile(image));
      if (!mounted) return;
      final text = result.text.trim();
      setState(() {
        _controller.text = text;
        _stage = _Stage.done;
        if (text.isEmpty) {
          _problem = 'No text found. Try again with more light, and hold the phone flat so the text fills the photo.';
        } else {
          _asCode = _looksLikeCode(text);
          if (_asCode) _language = _guessLanguage(text);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.done;
        _problem = "Couldn't read this photo: $e";
      });
    } finally {
      await recognizer.close();
    }
  }

  static bool _looksLikeCode(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return false;
    final symbols = RegExp(r'[{}()\[\];=<>]').allMatches(text).length;
    final codeLines = lines.where((l) {
      final t = l.trimRight();
      return t.endsWith(';') || t.endsWith('{') || t.endsWith('}') || t.endsWith(':') ||
          RegExp(r'^\s*(def|class|import|from|return|if|for|while|function|const|let|var|public|#include)\b').hasMatch(l);
    }).length;
    return symbols / text.length > 0.035 || codeLines / lines.length > 0.3;
  }

  static Language _guessLanguage(String t) {
    bool has(String p) => RegExp(p, multiLine: true).hasMatch(t);
    if (has(r'#include\s*<')) return Language.cpp;
    if (has(r'\bpublic\s+(static\s+)?(class|void)\b') || has(r'System\.out\.')) return Language.java;
    if (has(r'\bConsole\.Write|\bnamespace\s+\w+|\busing\s+System')) return Language.cSharp;
    if (has(r'\binterface\s+\w+\s*\{|:\s*(string|number|boolean)\b')) return Language.typeScript;
    if (has(r'\b(function|const|let)\b|console\.log|=>')) return Language.javaScript;
    if (has(r'\bvoid\s+main\s*\(|\bfinal\s+\w+\s*=|\bWidget\b')) return Language.dart;
    if (has(r'\bfunc\s+\w+\(|\bpackage\s+main\b|:=')) return Language.go;
    if (has(r'<\?php|\$\w+\s*=')) return Language.php;
    return Language.python;
  }

  void _add() {
    final text = _controller.text.trimRight();
    if (text.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    Navigator.pop<BlockEntity>(
      context,
      _asCode
          ? CodeBlockEntity(id: uuid.generate(), text: text, language: _language)
          : NoteBlockEntity(id: uuid.generate(), text: text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final hasText = _controller.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan text')),
      // The add bar is part of the body so it stays above the keyboard.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_image == null) _emptyState(context) else _photo(context),
                  if (_problem != null) ...[
                    const SizedBox(height: 12),
                    _notice(context, _problem!),
                  ],
                  if (_stage == _Stage.reading) ...[
                    const SizedBox(height: 16),
                    _reading(context),
                  ],
                  if (_stage == _Stage.done && (hasText || _problem == null)) ...[
                    const SizedBox(height: 20),
                    _result(context),
                  ],
                ],
              ),
            ),
            if (_stage == _Stage.done && hasText) _addBar(context, color),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(color: color.outlineVariant.withAlpha(160)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
            ),
            child: Icon(Icons.document_scanner_outlined, size: 30, color: color.primary),
          ),
          const SizedBox(height: 16),
          Text('Turn a photo into a block',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Code from a book, a whiteboard or a screen, or any printed text. You can fix the result before adding it.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: color.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a photo'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from gallery'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '// good light · hold the phone flat · text fills the photo',
            textAlign: TextAlign.center,
            style: monoStyle(context, size: 11, color: tokens.subtle),
          ),
        ],
      ),
    );
  }

  Widget _photo(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final busy = _stage == _Stage.reading;
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppBrand.radius),
          child: Container(
            color: color.surfaceContainerHighest,
            height: 220,
            child: Image.file(
              _image!,
              fit: BoxFit.contain,
              // Decode at screen size, not the photo's full size.
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image_outlined, color: color.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Retake'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Other photo'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reading(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: const LinearProgressIndicator(minHeight: 4),
        ),
        const SizedBox(height: 8),
        Text('Reading the text…', style: monoStyle(context, size: 12, color: tokens.subtle)),
      ],
    );
  }

  Widget _notice(BuildContext context, String message) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.errorContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: color.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color.onErrorContainer, fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final lines = _controller.text.trim().isEmpty ? 0 : _controller.text.trim().split('\n').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '// text found · $lines ${lines == 1 ? 'line' : 'lines'}',
                style: monoStyle(context, size: 13, weight: FontWeight.w700, color: color.primary),
              ),
            ),
            TextButton.icon(
              onPressed: lines == 0
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _controller.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied'), persist: false));
                    },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: _asCode ? tokens.codeBackground : color.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppBrand.radiusSmall),
            border: Border.all(color: color.outlineVariant.withAlpha(160)),
          ),
          child: TextField(
            controller: _controller,
            minLines: 4,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: _asCode
                ? monoStyle(context, size: 13).copyWith(height: 1.5)
                : textTheme.bodyLarge?.copyWith(height: 1.45),
            decoration: const InputDecoration(
              hintText: 'The text from the photo shows here. You can edit it.',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Check it before adding: photos can mix up 0 and O, or l and 1.',
            style: textTheme.bodySmall?.copyWith(color: tokens.subtle)),
      ],
    );
  }

  Widget _addBar(BuildContext context, ColorScheme color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: color.surface,
        border: Border(top: BorderSide(color: color.outlineVariant.withAlpha(160))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.notes_rounded, size: 18), label: Text('Text')),
                    ButtonSegment(value: true, icon: Icon(Icons.code_rounded, size: 18), label: Text('Code')),
                  ],
                  selected: {_asCode},
                  onSelectionChanged: (v) => setState(() => _asCode = v.first),
                ),
              ),
              if (_asCode) ...[
                const SizedBox(width: 8),
                LanguageDropDown(
                  language: _language,
                  selectLanguage: (l) {
                    if (l != null) setState(() => _language = l);
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
            label: Text(_asCode ? 'Add as a code block' : 'Add as a text block'),
          ),
        ],
      ),
    );
  }
}
