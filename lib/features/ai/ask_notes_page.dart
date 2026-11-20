import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../constants/themes.dart';
import '../../helpers/helper_methods.dart';
import '../../widgets/brand.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/note.dart';
import '../notes/presentation/bloc/note_bloc.dart';
import '../notes/presentation/bloc/note_event.dart';
import '../notes/presentation/bloc/note_state.dart';
import '../notes/presentation/pages/note_page.dart';
import 'ai_service.dart';
import 'ai_settings_page.dart';
import 'note_retrieval.dart';

/// Ask a question in plain words; the AI answers from your own notes and
/// shows which notes it used.
class AskNotesPage extends StatefulWidget {
  const AskNotesPage({super.key});

  @override
  State<AskNotesPage> createState() => _AskNotesPageState();
}

class _AskNotesPageState extends State<AskNotesPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _answer;
  String? _error;
  String _asked = '';
  List<NoteEntity> _sources = const [];
  bool _saved = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<NoteEntity> _allNotes() {
    final st = context.read<NoteBloc>().state;
    return st is NoteLoaded ? st.notes : const [];
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _busy) return;
    final settings = await AiService.instance.load();
    if (!mounted) return;
    if (!settings.isReady) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AiSettingsPage()));
      return;
    }
    final sources = NoteRetrieval.topNotes(_allNotes(), question);
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
      _saved = false;
      _asked = question;
      _sources = sources;
    });
    if (sources.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'No notes mention those words. Try other words, or check the spelling.';
      });
      return;
    }
    try {
      final answer = await AiService.instance
          .ask(NoteRetrieval.buildPrompt(question, sources), settings: settings);
      if (mounted) setState(() => _answer = answer.trim());
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveAsNote() {
    final answer = _answer;
    if (answer == null) return;
    final sourcesList = [
      for (var i = 0; i < _sources.length; i++)
        '${i + 1}. ${_sources[i].title.trim().isEmpty ? 'Untitled' : _sources[i].title.trim()}',
    ].join('\n');
    final note = NoteEntity(
      id: uuid.generate(),
      title: _asked.length > 60 ? '${_asked.substring(0, 60)}…' : _asked,
      tags: const ['ask'],
      lastModified: DateTime.now(),
      blocks: [
        MarkdownBlockEntity(id: uuid.generate(), text: answer),
        MarkdownBlockEntity(id: uuid.generate(), text: '### Sources\n$sourcesList'),
      ],
    );
    context.read<NoteBloc>().add(AddNoteEvent(note));
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Saved as a note tagged #ask.'),
      persist: false,
      duration: Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ask your notes')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const CommentLabel('ask a question, get an answer from your own notes'),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _ask(),
                decoration: InputDecoration(
                  hintText: 'e.g. how did I set up the docker volume?',
                  prefixIcon: const Icon(Icons.forum_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Ask',
                    onPressed: _busy ? null : _ask,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Only the few notes that match your words are sent to the AI you set up.',
                style: monoStyle(context, size: 11, color: tokens.subtle),
              ),
              const SizedBox(height: 20),
              if (_busy)
                Row(children: [
                  const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text('reading ${_sources.length} notes…', style: monoStyle(context, size: 13)),
                ]),
              if (_error != null)
                Card(
                  color: color.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_error!, style: TextStyle(color: color.onErrorContainer)),
                  ),
                ),
              if (_answer != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: MarkdownBody(
                      data: _answer!,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        code: monoStyle(context, size: 13),
                        codeblockDecoration: BoxDecoration(
                          color: tokens.codeBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _saved ? null : _saveAsNote,
                    icon: Icon(_saved ? Icons.check_rounded : Icons.note_add_outlined),
                    label: Text(_saved ? 'Saved' : 'Save as note'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _answer!));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Copied.'), persist: false));
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                ]),
              ],
              if (_sources.isNotEmpty && !_busy) ...[
                const SizedBox(height: 22),
                const CommentLabel('sources'),
                const SizedBox(height: 6),
                for (var i = 0; i < _sources.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text('${i + 1}', style: monoStyle(context, size: 11)),
                    ),
                    title: Text(_sources[i].title.trim().isEmpty
                        ? 'Untitled'
                        : _sources[i].title.trim()),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => NotePage(note: _sources[i]))),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
