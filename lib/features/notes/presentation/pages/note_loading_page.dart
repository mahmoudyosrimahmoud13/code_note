import 'package:flutter/material.dart';
import '../../domain/repositories/note_repository.dart';
import 'note_page.dart';
import '../../../../injection_container.dart';

class NoteLoadingPage extends StatefulWidget {
  final String noteId;
  const NoteLoadingPage({super.key, required this.noteId});

  @override
  State<NoteLoadingPage> createState() => _NoteLoadingPageState();
}

class _NoteLoadingPageState extends State<NoteLoadingPage> {
  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final result = await sl<NoteRepository>().getNoteById(widget.noteId);

    if (mounted) {
      result.fold(
        (failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load note.')),
          );
          Navigator.pop(context);
        },
        (note) {
          if (note != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => NotePage(note: note)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Note not found.')),
            );
            Navigator.pop(context);
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening note...'),
          ],
        ),
      ),
    );
  }
}
