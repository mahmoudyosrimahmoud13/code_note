import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../constants/themes.dart';
import '../../widgets/brand.dart';
import 'ai_service.dart';
import 'ai_settings_page.dart';

/// Opens the AI panel for a code block. Returns the answer as Markdown when
/// the person taps "Save to note", or null if they close it.
Future<String?> showAiExplainSheet(
  BuildContext context, {
  required AiAction action,
  required String language,
  required String code,
}) async {
  final settings = await AiService.instance.load();
  if (!context.mounted) return null;
  if (!settings.isReady) {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AiSettingsPage()));
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AiExplainSheet(action: action, language: language, code: code),
  );
}

class _AiExplainSheet extends StatefulWidget {
  const _AiExplainSheet({
    required this.action,
    required this.language,
    required this.code,
  });

  final AiAction action;
  final String language;
  final String code;

  @override
  State<_AiExplainSheet> createState() => _AiExplainSheetState();
}

class _AiExplainSheetState extends State<_AiExplainSheet> {
  String? _answer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _answer = null;
      _error = null;
    });
    try {
      final text = await AiService.instance
          .ask(widget.action.prompt(widget.language, widget.code));
      if (mounted) setState(() => _answer = text);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  const Text('✨ ', style: TextStyle(fontSize: 18)),
                  Expanded(
                    child: Text(widget.action.label,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _answer == null && _error == null
                  ? Center(
                      child: TerminalEmptyState(
                        command: 'ai ${widget.action.command} ${widget.language}',
                        output: 'thinking…',
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: color.error, size: 32),
                                const SizedBox(height: 12),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                Wrap(spacing: 8, children: [
                                  OutlinedButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const AiSettingsPage()),
                                    ),
                                    child: const Text('AI settings'),
                                  ),
                                  FilledButton(
                                      onPressed: _run, child: const Text('Try again')),
                                ]),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          child: MarkdownBody(
                            data: _answer!,
                            selectable: true,
                            styleSheet:
                                MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              code: monoStyle(context, size: 13, color: color.primary),
                              codeblockDecoration: BoxDecoration(
                                color: tokens.codeBackground,
                                borderRadius:
                                    BorderRadius.circular(AppBrand.radiusSmall),
                              ),
                            ),
                          ),
                        ),
            ),
            if (_answer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: color.outlineVariant)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Ask again',
                      onPressed: _run,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _answer!));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied')));
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        '### ✨ ${widget.action.savedTitle}\n\n${_answer!}',
                      ),
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text('Save to note'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
