import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/helper_methods.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/language.dart';
import '../notes/domain/entities/note.dart';
import '../notes/presentation/bloc/note_bloc.dart';
import '../notes/presentation/bloc/note_event.dart';
import '../notes/presentation/bloc/note_state.dart';
import '../notes/presentation/pages/note_page.dart';
import 'lesson_import.dart';

/// Where a note came from in inPace, for "Back to inPace" and "Export for
/// inPace".
class InpaceLink {
  const InpaceLink({required this.noteId, required this.hash, this.course, this.courseTitle, this.lesson,
      this.lessonTitle, this.taskId, this.back});

  final String noteId;
  final String hash;
  final String? course, courseTitle, lesson, lessonTitle, taskId, back;

  Map<String, Object?> toJson() => {
        'noteId': noteId, 'hash': hash, 'course': course, 'courseTitle': courseTitle, 'lesson': lesson,
        'lessonTitle': lessonTitle, 'taskId': taskId, 'back': back,
      };

  static InpaceLink fromJson(Map<String, dynamic> m) => InpaceLink(
        noteId: '${m['noteId']}',
        hash: '${m['hash']}',
        course: m['course'] as String?,
        courseTitle: m['courseTitle'] as String?,
        lesson: m['lesson'] as String?,
        lessonTitle: m['lessonTitle'] as String?,
        taskId: m['taskId'] as String?,
        back: m['back'] as String?,
      );
}

/// Opens lessons and practical tasks sent by inPace (the
/// "Practice in CodeNote" button) as notes. See the Project doc
/// claude/codenote-inpace-bridge.md.
class InpaceBridge {
  InpaceBridge._();

  static const _uuid = Uuid();
  static const _boxName = 'inpace_links';
  static const supportedVersion = 1;

  static Future<Box> _box() => Hive.isBoxOpen(_boxName) ? Future.value(Hive.box(_boxName)) : Hive.openBox(_boxName);

  /// The inPace link of a note, if it came from inPace.
  static Future<InpaceLink?> linkFor(String noteId) async {
    try {
      final box = await _box();
      for (final v in box.values) {
        if (v is! String) continue;
        final link = InpaceLink.fromJson(json.decode(v) as Map<String, dynamic>);
        if (link.noteId == noteId) return link;
      }
    } catch (_) {}
    return null;
  }

  static void _say(BuildContext context, String text) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), persist: false));

  /// A `codenote://open/…` link (or the web fallback address).
  static Future<void> openLink(BuildContext context, String link) async {
    final data = LessonImport.decodeLink(link);
    if (data == null) {
      _say(context, "That CodeNote link is broken or cut short.");
      return;
    }
    await openPayload(context, data);
  }

  /// A `.md` lesson file: front matter (if any) plus the Markdown.
  static Future<void> openMarkdownFile(BuildContext context, String path) async {
    final text = await File(path).readAsString();
    final (meta, body) = LessonImport.frontMatter(text);
    final name = path.split(Platform.pathSeparator).last;
    await openPayload(context, {
      ...meta,
      'codenote': 'lesson',
      'v': meta['v'] is int ? meta['v'] : 1,
      'title': meta['title'] ?? (name.toLowerCase().endsWith('.md') ? name.substring(0, name.length - 3) : name),
      'markdown': body,
    });
  }

  /// A fingerprint of the lesson (FNV-1a, stable across runs), to notice
  /// when inPace sends a changed lesson.
  static String _hash(String markdown, Object? task) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode('$markdown\u0000${json.encode(task)}')) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${markdown.length}-${h.toRadixString(16)}';
  }

  /// Makes (or finds) the note for a lesson payload and opens it.
  static Future<void> openPayload(BuildContext context, Map<String, dynamic> data) async {
    if (data['codenote'] != 'lesson') {
      _say(context, "CodeNote doesn't know this kind of link yet.");
      return;
    }
    final v = data['v'] is int ? data['v'] as int : 1;
    if (v > supportedVersion) {
      _say(context, 'This lesson needs a newer CodeNote. Update CodeNote and open it again.');
      return;
    }
    final markdown = '${data['markdown'] ?? ''}';
    final source = data['source'] is Map ? (data['source'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final task = data['task'] is Map ? (data['task'] as Map).cast<String, dynamic>() : null;
    final fallback = LessonImport.languageFor('${data['language'] ?? 'python'}') ?? Language.python;
    var title = '${data['title'] ?? source['lesson_title'] ?? 'Lesson'}'.trim();
    if (title.length > 200) title = title.substring(0, 200);
    final hash = _hash(markdown, task);
    final course = source['course'] as String?;
    final lesson = source['lesson'] as String?;
    final key = course == null || lesson == null ? null : '$course|$lesson|${task?['id'] ?? ''}';

    // The same lesson again: open the note you already have.
    if (key != null) {
      final box = await _box();
      final raw = box.get(key);
      if (raw is String && context.mounted) {
        final old = InpaceLink.fromJson(json.decode(raw) as Map<String, dynamic>);
        final state = context.read<NoteBloc>().state;
        final existing = state is NoteLoaded
            ? state.notes.where((n) => n.id == old.noteId && !n.isTrashed).firstOrNull
            : null;
        if (existing != null) {
          if (old.hash == hash) {
            _open(context, existing);
            return;
          }
          final choice = await showDialog<String>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('The lesson changed in inPace'),
              content: Text('You already have "${existing.title}". Open your note as it is, or get the new '
                  'version of the lesson as a new note? Your note stays either way.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, 'mine'), child: const Text('Open my note')),
                FilledButton(onPressed: () => Navigator.pop(c, 'new'), child: const Text('Get the new version')),
              ],
            ),
          );
          if (!context.mounted || choice == null) return;
          if (choice == 'mine') {
            _open(context, existing);
            return;
          }
        }
      }
    }

    final blocks = <BlockEntity>[];
    final from = [source['course_title'] ?? course, source['lesson_title'] ?? lesson].whereType<String>().join(' › ');
    if (from.isNotEmpty) {
      blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: '*From inPace: $from*'));
    }
    if (task != null && '${task['prompt'] ?? ''}'.trim().isNotEmpty) {
      blocks.add(MarkdownBlockEntity(id: _uuid.v4(), text: '**Task:** ${task['prompt']}'));
      blocks.add(CodeBlockEntity(id: _uuid.v4(), text: '', language: fallback));
    }
    blocks.addAll(LessonImport.blocks(markdown, fallback: fallback));
    final note = NoteEntity(
      id: _uuid.v4(),
      title: title.isEmpty ? 'Lesson' : title,
      tags: const ['inpace'],
      lastModified: DateTime.now(),
      blocks: blocks.isEmpty ? [MarkdownBlockEntity(id: _uuid.v4(), text: '*This lesson is empty.*')] : blocks,
    );
    final link = InpaceLink(
      noteId: note.id,
      hash: hash,
      course: course,
      courseTitle: source['course_title'] as String?,
      lesson: lesson,
      lessonTitle: source['lesson_title'] as String?,
      taskId: task?['id'] as String?,
      back: source['back'] as String?,
    );
    await (await _box()).put(key ?? 'note|${note.id}', json.encode(link.toJson()));
    if (!context.mounted) return;
    context.read<NoteBloc>().add(AddNoteEvent(note));
    _open(context, note);
  }

  static void _open(BuildContext context, NoteEntity note) {
    WidgetsBinding.instance.addPostFrameCallback((_) => navigateTo(toPage: NotePage(note: note)));
  }

  /// "Back to inPace": opens the lesson in inPace.
  static Future<void> back(BuildContext context, InpaceLink link) async {
    final target = link.back;
    var ok = false;
    if (target != null && target.isNotEmpty) {
      try {
        ok = await launchUrl(Uri.parse(target), mode: LaunchMode.externalNonBrowserApplication);
      } catch (_) {
        try {
          ok = await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
        } catch (_) {}
      }
    }
    if (!ok && context.mounted) {
      _say(context, "Couldn't open inPace. Is it installed on this device?");
    }
  }
}
