import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../features/notes/domain/entities/note.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/language.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/notes/presentation/bloc/note_bloc.dart';
import '../../features/notes/presentation/bloc/note_event.dart';
import '../../features/notes/presentation/pages/note_page.dart';
import '../util/code_languages.dart';
import '../util/image_helper.dart';
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
        // Mark the launch share as handled, so it isn't added again later.
        ReceiveSharingIntent.instance.reset();
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

    final images = <String>[];
    for (var file in media) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        _createNoteFromText(context, file.path);
      } else if (file.type == SharedMediaType.image) {
        images.add(file.path);
      } else if (file.type == SharedMediaType.file) {
        _createNoteFromFile(context, file.path);
      }
    }
    // Several shared photos become one note with all of them.
    if (images.isNotEmpty) _createNoteFromImages(context, images);
  }

  void _createNoteFromImages(BuildContext context, List<String> paths) async {
    final blocks = <BlockEntity>[];
    for (final path in paths) {
      try {
        final saved = await ImageHelper.persistImage(path);
        blocks.add(ImageBlockEntity(id: _uuid.v4(), imagePath: saved));
      } catch (e) {
        LogService().log("SharingService: Could not copy shared image: $e");
      }
    }
    if (blocks.isEmpty || !context.mounted) return;
    _openAndSave(
      context,
      NoteEntity(
        id: _uuid.v4(),
        title: paths.length == 1 ? 'Shared image' : 'Shared images',
        blocks: blocks,
        lastModified: DateTime.now(),
        tags: const ['shared'],
      ),
    );
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

    _openAndSave(context, note);
  }

  void _createNoteFromFile(BuildContext context, String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      final fileName = path.split('/').last;
      final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

      final language = languageForFileName(fileName);

      // Markdown and plain text become text blocks, not code.
      final BlockEntity block;
      if (extension == 'md' || extension == 'markdown') {
        block = MarkdownBlockEntity(id: _uuid.v4(), text: content);
      } else if (language == Language.none) {
        block = NoteBlockEntity(id: _uuid.v4(), text: content);
      } else {
        block = CodeBlockEntity(id: _uuid.v4(), text: content, language: language);
      }

      final note = NoteEntity(
        id: _uuid.v4(),
        title: fileName,
        blocks: [block],
        lastModified: DateTime.now(),
        tags: const ['shared', 'file'],
      );

      if (context.mounted) _openAndSave(context, note);
    } catch (e) {
      LogService().log("SharingService: Error reading file: $e");
      showMessage(
          message: "Couldn't open that file. CodeNote reads text and code files.",
          type: SnackType.faild);
    }
  }

  /// Saves the shared note first, so nothing is lost even if it's closed
  /// right away, then opens it.
  void _openAndSave(BuildContext context, NoteEntity note) {
    context.read<NoteBloc>().add(AddNoteEvent(note));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigateTo(toPage: NotePage(note: note));
    });
  }
}
