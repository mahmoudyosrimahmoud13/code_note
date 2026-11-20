import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/util/note_share_helper.dart';
import '../../injection_container.dart' as di;
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import 'backup_service.dart';

/// The standard way to share notes: a `.codenote` file. It can hold one
/// note, a folder (with its run order) or a full backup, always with the
/// images and the saved data of mini apps. Opening one merges it in.
class CodenoteFiles {
  CodenoteFiles._();

  static BackupService get _service => di.sl<BackupService>();

  static const typeGroup = XTypeGroup(
    label: 'CodeNote file',
    extensions: ['codenote', 'json'],
    mimeTypes: ['application/json', 'application/octet-stream'],
    uniformTypeIdentifiers: ['public.json', 'public.data'],
  );

  static Future<void> shareNote(BuildContext context, NoteEntity note) async {
    await _share(context, await _service.exportNote(note), BackupService.shareFileName(note.title));
  }

  static Future<void> shareFolder(BuildContext context, NoteGroupEntity group) async {
    await _share(context, await _service.exportFolder(group), BackupService.shareFileName(group.name));
  }

  static Future<void> _share(BuildContext context, Uint8List bytes, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await NoteShareHelper.saveOrShareBytes(
        bytes,
        fileName: name,
        mimeType: 'application/json',
        typeLabel: 'CodeNote file',
        shareText: 'A CodeNote note. Open it with CodeNote.',
      );
      if (saved != null) {
        messenger.showSnackBar(SnackBar(content: Text('Saved $name'), persist: false));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't share: $e"), persist: false));
    }
  }

  /// Imports a `.codenote` file's notes, folders, images and app data.
  /// Notes you already have are only replaced by newer copies.
  static Future<String> importBytes(Uint8List bytes) async => (await _service.restore(bytes)).summary;

  /// Lets the person pick a `.codenote` file and imports it.
  static Future<void> pickAndImport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    try {
      final summary = await importBytes(await file.readAsBytes());
      messenger.showSnackBar(SnackBar(content: Text('Imported: $summary'), persist: false));
    } on BackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), persist: false));
    }
  }
}
