import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import 'package:uuid/uuid.dart';

import '../../constants/themes.dart';
import '../../features/ai/ai_explain_sheet.dart';
import '../../features/ai/ai_service.dart';
import '../../features/notes/presentation/widgets/code_image_sheet.dart';
import '../../core/util/code_languages.dart';
import '../../core/util/note_share_helper.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';
import '../../helpers/helper_methods.dart';
import '../../features/runner/code_runner.dart';
import '../../features/runner/note_scope.dart';
import '../../features/runner/notebook_focus.dart';
import '../../features/runner/snippets.dart';
import '../../features/runner/run_manager.dart';
import '../../features/runner/run_panel.dart';
import '../../features/runner/rich_output_view.dart';
import '../../features/runner/runtimes.dart';
import '../../core/util/image_helper.dart';
import '../../features/runner/running_indicator.dart';
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

  /// Focus on the block itself, not the code: Jupyter's command mode,
  /// where single keys (A, B, D D, M…) act on the block.
  final FocusNode _blockFocus = FocusNode(debugLabel: 'code block', skipTraversal: true);
  late Language _language;

  /// How many digits the biggest line number has. The gutter grows when
  /// it changes (9 to 10 lines, 99 to 100), so numbers never wrap.
  int _digits = 1;

  /// flutter_code_editor takes 16 px for the error column and 16 px for
  /// the folding column out of the gutter width, even when both are
  /// hidden. Without adding them back, the numbers get almost no room and
  /// two-digit numbers wrap onto two rows.
  static const _hiddenGutterColumns = 32.0;
  static const _gutterMargin = 8.0;
  static const _gutterFontSize = 12.0;

  static int _digitsFor(String text) =>
      ('\n'.allMatches(text).length + 1).toString().length;

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
    _runRole = widget.codeEntity.runRole;
    _controller = CodeController(
      text: widget.text ?? '',
      language: languageInfo(_language).mode,
    );
    _digits = _digitsFor(_controller.text);
    _controller.addListener(_onTextChanged);
    // Only show the symbol bar while editing.
    _focusNode.addListener(_onFocus);
    _blockFocus.addListener(_onFocus);
    NotebookFocus.register(widget.id, _focusFromNote);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  /// Another block (or the note) moves the keyboard here.
  void _focusFromNote(bool edit) {
    if (!mounted) return;
    Scrollable.ensureVisible(context,
        duration: const Duration(milliseconds: 160), alignment: 0.15, curve: Curves.easeOut);
    (edit ? _focusNode : _blockFocus).requestFocus();
  }

  LogicalKeyboardKey? _lastKey;
  DateTime? _lastKeyAt;

  /// True on the second press of [key] in a row (D D, I I, 0 0).
  bool _twice(LogicalKeyboardKey key) {
    final now = DateTime.now();
    final hit = _lastKey == key &&
        _lastKeyAt != null &&
        now.difference(_lastKeyAt!) < const Duration(milliseconds: 800);
    _lastKey = hit ? null : key;
    _lastKeyAt = now;
    return hit;
  }

  /// Runs the block if it can run and has code (Shift+Enter on an empty or
  /// non-runnable block just moves on, like Jupyter).
  void _runIfPossible() {
    if (_controller.text.trim().isEmpty || !_runnable(context)) return;
    _run();
  }

  /// Jupyter-style shortcuts. See [notebookShortcuts].
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    final inCode = primary == _focusNode;
    final selected = primary == _blockFocus;
    // The answer box under the output and other fields keep their keys.
    if (!inCode && !selected) return KeyEventResult.ignored;

    final keys = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final enter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final notebook = NoteScope.of(context)?.notebook;

    if (enter && keys.isShiftPressed && !ctrl && !keys.isAltPressed) {
      _runIfPossible();
      if (notebook != null) {
        notebook.next(widget.id);
      } else {
        _blockFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (enter && ctrl) {
      _runIfPossible();
      return KeyEventResult.handled;
    }
    if (enter && keys.isAltPressed) {
      _runIfPossible();
      notebook?.insert(widget.id, above: false);
      return KeyEventResult.handled;
    }

    if (inCode) {
      if (key == LogicalKeyboardKey.escape) {
        _blockFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Command mode: the block is selected, the cursor isn't in the code.
    if (ctrl || keys.isAltPressed) return KeyEventResult.ignored;
    if (enter) {
      _focusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _blockFocus.unfocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      notebook?.insert(widget.id, above: true);
    } else if (key == LogicalKeyboardKey.keyB) {
      notebook?.insert(widget.id, above: false);
    } else if (key == LogicalKeyboardKey.keyD) {
      if (_twice(key)) {
        if (notebook != null) {
          notebook.delete(widget.id);
        } else {
          widget.delete?.call(widget.id);
        }
      }
    } else if (key == LogicalKeyboardKey.keyM) {
      notebook?.toMarkdown(widget.id);
    } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyK) {
      notebook?.previous(widget.id);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyJ) {
      notebook?.next(widget.id);
    } else if (key == LogicalKeyboardKey.keyI) {
      if (_twice(key)) RunManager.instance.sessionFor(widget.id)?.stop();
    } else if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      if (_twice(LogicalKeyboardKey.digit0)) {
        final noteId = NoteScope.of(context)?.noteId;
        if (noteId != null) {
          RunManager.instance.restartKernel(noteId);
          showMessage(message: 'Python kernel restarted. Variables are cleared.');
        }
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _onTextChanged() {
    final digits = _digitsFor(_controller.text);
    if (digits != _digits && mounted) setState(() => _digits = digits);
  }

  /// Width of the line number column: enough for the widest number, at
  /// least two digits so it doesn't jump at line 10.
  double _gutterWidth(BuildContext context) {
    final style = monoStyle(context, size: _gutterFontSize);
    final painter = TextPainter(
      text: TextSpan(text: '0' * (_digits < 2 ? 2 : _digits), style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _hiddenGutterColumns + _gutterMargin + width + 6;
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    NotebookFocus.unregister(widget.id, _focusFromNote);
    _focusNode.removeListener(_onFocus);
    _blockFocus.removeListener(_onFocus);
    _focusNode.dispose();
    _blockFocus.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged?.call(
      widget.codeEntity.copyWith(text: _controller.text, language: _language, runRole: _runRole),
    );
  }

  /// What Run folder does with this block (see [RunRole]).
  RunRole _runRole = RunRole.normal;

  @override
  void didUpdateWidget(covariant CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another block became the note's main block, so this one isn't any more.
    final role = widget.codeEntity.runRole;
    if (role != oldWidget.codeEntity.runRole && role != _runRole) {
      setState(() => _runRole = role);
    }
  }

  void _setRunRole(RunRole role) {
    setState(() => _runRole = _runRole == role ? RunRole.normal : role);
    _notify();
    showMessage(
        message: switch (_runRole) {
      RunRole.main => 'Primary block: it runs last when you run the note or folder, and keeps running.',
      RunRole.background => 'Keeps running: the next block starts without waiting for this one.',
      RunRole.skip => 'Skipped when running the note or folder. Its own ▶ still works.',
      RunRole.normal => 'Runs in order, and the next block waits for it.',
    });
  }

  /// Puts [symbol] where the cursor is (not at the end of the code),
  /// replacing any selected text.
  /// Data science snippets: typed in at the cursor, on a line of their own.
  Future<void> _insertSnippet() async {
    final snippet = await pickSnippet(context);
    if (snippet == null || !mounted) return;
    final value = _controller.value;
    final text = value.text;
    final at = value.selection.isValid ? value.selection.start.clamp(0, text.length) : text.length;
    final before = at == 0 || text[at - 1] == '\n' ? '' : '\n';
    final after = at < text.length && text[at] != '\n' ? '\n' : '';
    _insert('$before${snippet.code}$after', after.length);
  }

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

  /// Gets a ▶: a runnable language, inside a note, and for JavaScript only
  /// when the note isn't a web page.
  bool _runnable(BuildContext context) {
    final scope = NoteScope.of(context);
    if (scope == null || !CodeRunner.canRun(_language)) return false;
    final web = _language == Language.javaScript || _language == Language.typeScript;
    return !(web && scope.isWebPage);
  }

  void _run() {
    final scope = NoteScope.of(context);
    if (scope == null) return;
    final code = _controller.text;
    if (code.trim().isEmpty) {
      showMessage(message: 'Write some code first.');
      return;
    }
    RunManager.instance.run(
      blockId: widget.id,
      title: scope.title,
      spaceKey: scope.spaceKey,
      language: _language,
      code: code,
      noteId: scope.noteId,
      role: _runRole,
    );
  }

  /// Saves the output under the code block, in order: text as a code
  /// block, plots as image blocks, tables as Markdown tables.
  Future<void> _saveOutput(RunSession session) async {
    final blocks = <BlockEntity>[];
    final text = <String>[];
    void flush() {
      final t = text.join('\n').trimRight();
      text.clear();
      if (t.isEmpty) return;
      const limit = 20000;
      final cut = t.length > limit ? '…\n${t.substring(t.length - limit)}' : t;
      blocks.add(MarkdownBlockEntity(id: const Uuid().v4(), text: '```text\n$cut\n```'));
    }

    for (final line in session.lines) {
      final rich = RichOutput.parse(line);
      if (rich == null) {
        text.add(RunningProcess.plain(line));
        continue;
      }
      flush();
      switch (rich.kind) {
        case 'image':
          final saved = await ImageHelper.persistImage(rich.path);
          blocks.add(ImageBlockEntity(id: const Uuid().v4(), imagePath: saved));
        case 'table':
          final table = OutputTable.read(rich.path);
          if (table != null) blocks.add(MarkdownBlockEntity(id: const Uuid().v4(), text: table.toMarkdown()));
        case 'markdown':
          try {
            blocks.add(MarkdownBlockEntity(id: const Uuid().v4(), text: await File(rich.path).readAsString()));
          } catch (_) {}
        case 'missing':
          break; // the download card isn't output
        default:
          blocks.add(MarkdownBlockEntity(
              id: const Uuid().v4(),
              text: '*Interactive output (${rich.note.isEmpty ? 'HTML' : rich.note}): run the block again to open it.*'));
      }
    }
    flush();
    if (blocks.isEmpty || !mounted) return;
    var after = widget.id;
    for (final block in blocks) {
      widget.onInsertAfter!(after, block);
      after = block.id;
    }
    showMessage(message: 'Output saved under the code block.');
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
    final selected = _blockFocus.hasPrimaryFocus;

    return Focus(
      focusNode: _blockFocus,
      onKeyEvent: _onKey,
      child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: tokens.codeBackground,
        borderRadius: BorderRadius.circular(AppBrand.radius),
        border: Border.all(
          color: editing
              ? color.primary.withAlpha(160)
              : selected
                  ? color.tertiary
                  : color.outlineVariant,
          width: selected ? 2 : 1,
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
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                 LanguageDropDown(
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
                 if (_runRole != RunRole.normal && _runnable(context))
                   Padding(
                     padding: const EdgeInsets.only(left: 4),
                     child: Tooltip(
                       message: switch (_runRole) {
                         RunRole.main => 'Primary: runs last and keeps running',
                         RunRole.background => 'Keeps running: the next block does not wait',
                         _ => 'Skipped when running the note or folder',
                       },
                       child: Text(
                           switch (_runRole) {
                             RunRole.main => '★ primary',
                             RunRole.background => '↻ keeps running',
                             _ => 'skip',
                           },
                           style: monoStyle(context,
                               size: 11.5,
                               color: _runRole == RunRole.main ? tokens.pin : tokens.subtle)),
                     ),
                   ),
                ]),
              ),
              quickActions: [
                if (_runnable(context))
                  ListenableBuilder(
                    listenable: RunManager.instance,
                    builder: (context, _) {
                      final running = RunManager.instance.sessionFor(widget.id)?.running ?? false;
                      return IconButton(
                        tooltip: running ? 'Running · tap to stop' : 'Run in the sandbox',
                        visualDensity: VisualDensity.compact,
                        icon: RunButtonIcon(running: running),
                        onPressed: running ? () => RunManager.instance.sessionFor(widget.id)?.stop() : _run,
                      );
                    },
                  ),
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
                if (_language == Language.python)
                  BlockAction(
                    label: 'Insert a data science snippet',
                    icon: Icons.auto_awesome_motion_rounded,
                    onTap: _insertSnippet,
                  ),
                if (_runnable(context)) ...[
                  BlockAction(
                    label: _runRole == RunRole.main ? 'Unset primary block' : '★ Primary block (runs last)',
                    icon: Icons.star_outline_rounded,
                    onTap: () => _setRunRole(RunRole.main),
                  ),
                  BlockAction(
                    label: _runRole == RunRole.background ? 'Wait for this block again' : 'Keep running (don\'t wait)',
                    icon: Icons.all_inclusive_rounded,
                    onTap: () => _setRunRole(RunRole.background),
                  ),
                  BlockAction(
                    label: _runRole == RunRole.skip ? 'Run with the note again' : 'Skip when running the note',
                    icon: Icons.block_rounded,
                    onTap: () => _setRunRole(RunRole.skip),
                  ),
                ],
                BlockAction(
                  label: 'Share as image',
                  icon: Icons.image_outlined,
                  onTap: () {
                    if (_controller.text.trim().isEmpty) {
                      showMessage(message: 'Write some code first.');
                      return;
                    }
                    showCodeImageSheet(
                      context,
                      code: _controller.text,
                      language: _language,
                    );
                  },
                ),
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
                width: _gutterWidth(context),
                margin: _gutterMargin,
                showFoldingHandles: false,
                showErrors: false,
                textStyle: monoStyle(context,
                    size: _gutterFontSize,
                    color: tokens.subtle.withAlpha(150)),
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
                        if (_language == Language.python)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(40, 32),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                backgroundColor: color.primaryContainer,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _insertSnippet,
                              icon: const Icon(Icons.auto_awesome_motion_rounded, size: 16),
                              label: const Text('Snippet'),
                            ),
                          ),
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
          ListenableBuilder(
            listenable: RunManager.instance,
            builder: (context, _) {
              final session = RunManager.instance.sessionFor(widget.id);
              if (session == null) return const SizedBox.shrink();
              return RunPanel(
                session: session,
                onSaveOutput: widget.onInsertAfter == null ? null : _saveOutput,
              );
            },
          ),
        ],
      ),
    ),
    );
  }
}
