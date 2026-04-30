import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../features/notes/domain/entities/note.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';
import '../../features/notes/presentation/pages/note_page.dart';
import '../../helpers/helper_methods.dart';
import 'log_service.dart';
import 'package:uuid/uuid.dart';

class SharingService {
  static final SharingService _instance = SharingService._internal();
  factory SharingService() => _instance;
  SharingService._internal();

  StreamSubscription? _intentDataStreamSubscription;
  final _uuid = const Uuid();

  void init(BuildContext context) {
    // Sharing intent is only supported on mobile platforms
    if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) {
      LogService().log("SharingService: Sharing intent not supported on this platform.");
      return;
    }

    try {
      // For sharing images/files coming from outside the app while the app is in memory
      _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
        _handleSharedMedia(context, value);
      }, onError: (err) {
        LogService().log("SharingService: getIntentDataStream error: $err");
      });

      // For sharing images/files coming from outside the app while the app is closed
      ReceiveSharingIntent.instance.getInitialMedia().then((value) {
        _handleSharedMedia(context, value);
      }).catchError((err) {
        LogService().log("SharingService: getInitialMedia error: $err");
      });
    } catch (e) {
      LogService().log("SharingService: Initialization failed: $e");
    }
  }

  void dispose() {
    _intentDataStreamSubscription?.cancel();
  }

  void _handleSharedMedia(BuildContext context, List<SharedMediaFile> media) async {
    if (media.isEmpty) return;

    LogService().log("SharingService: Handling shared media: ${media.length} items");

    for (var file in media) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        _createNoteFromText(context, file.path);
      } else if (file.type == SharedMediaType.file) {
        _createNoteFromFile(context, file.path);
      }
    }
  }

  void _createNoteFromText(BuildContext context, String text) {
    final note = NoteEntity(
      id: _uuid.v4(),
      title: 'Shared Snippet',
      blocks: [
        NoteBlockEntity(id: _uuid.v4(), text: text),
      ],
      lastModified: DateTime.now(),
      tags: const ['shared'],
    );

    _navigateToNote(context, note);
  }

  void _createNoteFromFile(BuildContext context, String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split('/').last;
      final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

      final language = _mapExtensionToLanguage(extension);

      final note = NoteEntity(
        id: _uuid.v4(),
        title: fileName,
        blocks: [
          CodeBlockEntity(
            id: _uuid.v4(),
            text: content,
            language: language,
          ),
        ],
        lastModified: DateTime.now(),
        tags: const ['shared', 'file'],
      );

      _navigateToNote(context, note);
    } catch (e) {
      LogService().log("SharingService: Error reading file: $e");
    }
  }

  Language _mapExtensionToLanguage(String ext) {
    switch (ext) {
      case 'py': return Language.python;
      case 'dart': return Language.dart;
      case 'js': return Language.javaScript;
      case 'ts': return Language.typeScript;
      case 'cs': return Language.cSharp;
      case 'go': return Language.go;
      case 'java': return Language.java;
      case 'cpp':
      case 'cxx':
      case 'h':
      case 'hpp': return Language.cpp;
      case 'php': return Language.php;
      case 'ino': return Language.arduino;
      case 'sh': return Language.bash;
      case 'kt': return Language.kotlin;
      case 'sql': return Language.sql;
      case 'pgsql': return Language.pgSql;
      case 'json': return Language.json;
      case 'html': return Language.html;
      case 'css': return Language.css;
      case 'asm':
      case 's': return Language.x86Assembly;
      case 'dockerfile': return Language.docker;
      default: return Language.none;
    }
  }

  void _navigateToNote(BuildContext context, NoteEntity note) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigateTo(toPage: NotePage(note: note));
    });
  }
}
