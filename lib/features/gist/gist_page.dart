import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/themes.dart';
import '../../widgets/brand.dart';
import '../notes/domain/entities/note.dart';
import '../notes/presentation/pages/note_page.dart';
import 'gist_service.dart';

/// Import a GitHub Gist as a note, and manage the token used for export.
class GistPage extends StatefulWidget {
  const GistPage({super.key});

  @override
  State<GistPage> createState() => _GistPageState();
}

class _GistPageState extends State<GistPage> {
  final _link = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  bool _showToken = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    GistService.instance.loadToken().then((t) {
      if (mounted) setState(() => _token.text = t);
    });
  }

  @override
  void dispose() {
    _link.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await GistService.instance.importGist(_link.text);
      if (!mounted) return;
      // Opens like a new note: it is saved as soon as you leave the page.
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => NotePage(note: note)));
    } on GistException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToken() async {
    await GistService.instance.saveToken(_token.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Token saved on this device.'), persist: false));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub Gist')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const CommentLabel('import a gist as a note'),
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                autofocus: true,
                onSubmitted: (_) => _import(),
                style: monoStyle(context, size: 13),
                decoration: const InputDecoration(
                  hintText: 'https://gist.github.com/user/1a2b3c… or the id',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_rounded),
                  label: const Text('Import'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: color.error)),
              ],
              const SizedBox(height: 32),
              const CommentLabel('export (optional)'),
              const SizedBox(height: 6),
              Text(
                'To upload a note as a gist, paste a GitHub token that has only the "gist" '
                'permission. It stays on this device. Then use "Upload as gist" in a note\'s ⋯ menu.',
                style: TextStyle(color: tokens.subtle),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _token,
                obscureText: !_showToken,
                style: monoStyle(context, size: 13),
                decoration: InputDecoration(
                  hintText: 'ghp_… or github_pat_…',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showToken ? 'Hide' : 'Show',
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: _saveToken, child: const Text('Save token')),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(
                        text: 'https://github.com/settings/tokens/new?scopes=gist&description=CodeNote'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Link copied. Open it in your browser to make a token.'),
                        persist: false));
                  },
                  child: const Text('Copy "make a token" link'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uploads [note] as a secret gist and copies the link.
Future<void> exportNoteToGist(BuildContext context, NoteEntity note) async {
  final messenger = ScaffoldMessenger.of(context);
  final token = await GistService.instance.loadToken();
  if (!context.mounted) return;
  if (token.isEmpty) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const GistPage()));
    return;
  }
  messenger.showSnackBar(const SnackBar(
      content: Text('Uploading to GitHub…'), persist: false, duration: Duration(seconds: 2)));
  try {
    final url = await GistService.instance.exportNote(note);
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(
        content: Text('Uploaded as a secret gist. Link copied: $url'),
        persist: false,
        duration: const Duration(seconds: 6)));
  } on GistException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message), persist: false));
  }
}
