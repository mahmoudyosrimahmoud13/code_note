import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import 'package:uuid/uuid.dart';

import '../../constants/themes.dart';
import '../../features/ai/ai_explain_sheet.dart';
import '../../features/ai/ai_service.dart';
import '../../core/util/code_languages.dart';
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
    super.dragHandle,
    super.onInsertAfter,
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
      language: languageInfo(_language).mode,
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

  Future<void> _askAi(AiAction action) async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      showMessage(message: 'Write some code first, then ask about it.');
      return;
    }
    final answer = await showAiExplainSheet(
      context,
      action: action,
      language: languageInfo(_language).label,
      code: code,
    );
    if (answer != null && widget.onInsertAfter != null) {
      widget.onInsertAfter!(
        widget.id,
        MarkdownBlockEntity(id: const Uuid().v4(), text: answer),
      );
      showMessage(message: 'Saved under the code block.');
    }
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
              handle: widget.dragHandle,
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
                      _controller.language = languageInfo(lang).mode;
                    });
                    _notify();
                  },
                ),
              ),
              quickActions: [
                PopupMenuButton<AiAction>(
                  tooltip: 'Ask AI about this code',
                  icon: const Text('✨', style: TextStyle(fontSize: 16)),
                  onSelected: _askAi,
                  itemBuilder: (context) => [
                    for (final action in AiAction.values)
                      PopupMenuItem(value: action, child: Text(action.label)),
                  ],
                ),
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
