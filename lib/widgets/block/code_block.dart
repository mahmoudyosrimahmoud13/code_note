import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/highlight_core.dart' as highlight;
import 'package:highlight/languages/arduino.dart';
import 'package:highlight/languages/armasm.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/django.dart';
import 'package:highlight/languages/dockerfile.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/htmlbars.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/pgsql.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/x86asm.dart';

import '../../constants/themes.dart';
import '../../core/util/note_share_helper.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';
import '../../helpers/helper_methods.dart';
import '../language_drop_down.dart';
import 'block.dart';
import 'block_frame.dart';

class CodeBlock extends Block {
  const CodeBlock({
    super.key,
    required super.entity,
    super.moveUp,
    super.moveDown,
    super.delete,
    super.onChanged,
  });

  CodeBlockEntity get codeEntity => entity as CodeBlockEntity;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  late final CodeController _controller;
  final FocusNode _focusNode = FocusNode();
  late Language _language;

  /// Symbols that are slow to reach on a phone keyboard.
  /// The second value is how far to step back so the cursor lands inside.
  static const _symbols = <(String, int)>[
    ('  ', 0),
    ('{}', 1),
    ('()', 1),
    ('[]', 1),
    ('""', 1),
    ("''", 1),
    (';', 0),
    (':', 0),
    ('=', 0),
    ('=>', 0),
    ('<>', 1),
    ('#', 0),
    ('_', 0),
  ];

  @override
  void initState() {
    super.initState();
    _language = widget.codeEntity.language;
    _controller = CodeController(
      text: widget.text ?? '',
      language: _modeFor(_language),
    );
    // Only show the symbol bar while editing.
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  highlight.Mode _modeFor(Language lang) {
    switch (lang) {
      case Language.python:
        return python;
      case Language.cSharp:
        return cs;
      case Language.dart:
        return dart;
      case Language.go:
        return go;
      case Language.java:
        return java;
      case Language.javaScript:
        return javascript;
      case Language.typeScript:
        return typescript;
      case Language.cpp:
        return cpp;
      case Language.php:
        return php;
      case Language.arduino:
        return arduino;
      case Language.armAssembly:
        return armasm;
      case Language.x86Assembly:
        return x86Asm;
      case Language.bash:
        return bash;
      case Language.django:
        return django;
      case Language.html:
        return htmlbars;
      case Language.css:
        return css;
      case Language.docker:
        return dockerfile;
      case Language.kotlin:
        return kotlin;
      case Language.sql:
        return sql;
      case Language.pgSql:
        return pgsql;
      case Language.json:
        return json;
      default:
        return python;
    }
  }

  void _notify() {
    widget.onChanged?.call(
      widget.codeEntity.copyWith(text: _controller.text, language: _language),
    );
  }

  /// Puts [symbol] where the cursor is (not at the end of the code),
  /// replacing any selected text.
  void _insert(String symbol, int stepBack) {
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final newText = text.replaceRange(start, end, symbol);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: start + symbol.length - stepBack,
      ),
    );
    _focusNode.requestFocus();
    _notify();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    HapticFeedback.lightImpact();
    showMessage(message: 'Copied. Ready to paste.');
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final editing = _focusNode.hasFocus;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: tokens.codeBackground,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(
          color: editing ? color.primary.withAlpha(160) : color.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
            child: BlockHeader(
              label: 'code',
              icon: Icons.code_rounded,
              leading: Align(
                alignment: Alignment.centerLeft,
                child: LanguageDropDown(
                  language: _language,
                  selectLanguage: (lang) {
                    if (lang == null) return;
                    setState(() {
                      _language = lang;
                      _controller.language = _modeFor(lang);
                    });
                    _notify();
                  },
                ),
              ),
              quickActions: [
                BlockQuickAction(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy code',
                  onPressed: _copy,
                ),
              ],
              extraActions: [
                BlockAction(
                  label: 'Share as file',
                  icon: Icons.ios_share_rounded,
                  onTap: () => NoteShareHelper.shareBlockAsFile(
                    widget.codeEntity.copyWith(
                        text: _controller.text, language: _language),
                    'Code Block',
                    _language,
                  ),
                ),
              ],
              onMoveUp: widget.moveUp == null ? null : () => widget.moveUp!(widget.id),
              onMoveDown:
                  widget.moveDown == null ? null : () => widget.moveDown!(widget.id),
              onDelete: widget.delete == null ? null : () => widget.delete!(widget.id),
            ),
          ),
          CodeTheme(
            data: CodeThemeData(styles: tokens.codeTheme),
            child: CodeField(
              controller: _controller,
              focusNode: _focusNode,
              background: Colors.transparent,
              minLines: 3,
              textStyle: monoStyle(context, size: 13.5),
              padding: const EdgeInsets.only(bottom: 12, right: 8),
              gutterStyle: GutterStyle(
                width: 44,
                margin: 8,
                showFoldingHandles: false,
                showErrors: false,
                textStyle: monoStyle(context,
                    size: 12, color: tokens.subtle.withAlpha(150)),
              ),
              onChanged: (_) => _notify(),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: editing
                // Taps here count as "inside" the code field, so the
                // keyboard stays open while inserting symbols.
                ? TextFieldTapRegion(child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.surfaceContainer,
                      border: Border(top: BorderSide(color: color.outlineVariant)),
                    ),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final (symbol, back) in _symbols)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 6),
                            child: Semantics(
                              button: true,
                              label: symbol.trim().isEmpty
                                  ? 'Insert indent'
                                  : 'Insert $symbol',
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(40, 32),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  backgroundColor: color.surfaceContainerHigh,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _insert(symbol, back),
                                child: Text(
                                  symbol.trim().isEmpty ? 'tab' : symbol,
                                  style: monoStyle(context,
                                      size: 13,
                                      weight: FontWeight.w700,
                                      color: color.primary),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ))
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
