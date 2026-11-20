import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

import '../../constants/app_info.dart';
import '../../core/services/log_service.dart';
import '../../core/util/image_helper.dart';
import '../notes/data/models/note_group_model.dart';
import '../notes/data/models/note_model.dart';
import '../notes/domain/entities/block.dart';
import '../notes/domain/entities/note.dart';
import '../notes/domain/entities/note_group.dart';
import '../notes/domain/repositories/note_repository.dart';

/// What happened during a restore.
class RestoreResult {
  const RestoreResult({
    required this.added,
    required this.updated,
    required this.kept,
    required this.folders,
  });

  /// Notes that didn't exist here yet.
  final int added;

  /// Notes that existed, where the backup's copy was newer.
  final int updated;

  /// Notes that existed, where this device's copy was newer (left alone).
  final int kept;

  /// Folders added or merged.
  final int folders;

  String get summary {
    final parts = <String>[
      if (added > 0) '$added added',
      if (updated > 0) '$updated updated',
      if (kept > 0) '$kept already newer here',
      if (folders > 0) '$folders ${folders == 1 ? 'folder' : 'folders'}',
    ];
    return parts.isEmpty ? 'Nothing new in that backup.' : 'Restored: ${parts.join(', ')}.';
  }
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Backup and restore of everything: notes, folders and the images they use.
///
/// A backup is one JSON file (`.codenote`). Images are stored inside it, so a
/// backup moved to another device is complete.
class BackupService {
  BackupService(this.repository);

  final NoteRepository repository;

  static const format = 'codenote-backup';
  static const extension = 'codenote';
  static const _boxName = 'appBox';
  static const _autoFolderKey = 'AUTO_BACKUP_FOLDER';
  static const _lastAutoKey = 'AUTO_BACKUP_LAST';
  static const keepAutoBackups = 10;

  /// Daily backups to a folder work on Windows and Linux. macOS doesn't let
  /// an app keep writing to a chosen folder after a restart.
  static bool get autoBackupSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  String fileName([DateTime? at]) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'codenote-backup-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}.$extension';
  }

  // ─── Export ─────────────────────────────────────────────

  Future<Uint8List> export() async {
    final notes = (await repository.getNotes()).getOrElse(() => const []);
    final groups = (await repository.getGroups()).getOrElse(() => const []);

    final images = <String, String>{};
    if (!kIsWeb) {
      for (final note in notes) {
        for (final block in note.blocks.whereType<ImageBlockEntity>()) {
          final path = block.imagePath;
          if (path == null || path.startsWith('http')) continue;
          final file = File(path);
          final key = p.basename(path);
          if (images.containsKey(key) || !await file.exists()) continue;
          images[key] = base64Encode(await file.readAsBytes());
        }
      }
    }

    final data = {
      'format': format,
      'formatVersion': 1,
      'appVersion': appVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'notes': [for (final n in notes) NoteModel.fromEntity(n).toJson()],
      'groups': [for (final g in groups) NoteGroupModel.fromEntity(g).toJson()],
      'images': images,
    };
    return Uint8List.fromList(utf8.encode(json.encode(data)));
  }

  // ─── Restore ────────────────────────────────────────────

  Future<RestoreResult> restore(Uint8List bytes) async {
    Map<String, dynamic> data;
    try {
      data = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException("That file isn't a CodeNote backup.");
    }
    if (data['format'] != format) {
      throw BackupException("That file isn't a CodeNote backup.");
    }

    // 1. Put the images back on this device and remember their new paths.
    final newPaths = <String, String>{};
    final images = (data['images'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (images.isNotEmpty && !kIsWeb) {
      final dir = Directory(p.join(
          (await imagesBaseDir()).path, 'persistent_images'));
      await dir.create(recursive: true);
      for (final entry in images.entries) {
        final target = File(p.join(dir.path, p.basename(entry.key)));
        if (!await target.exists()) {
          await target.writeAsBytes(base64Decode(entry.value as String));
        }
        newPaths[entry.key] = target.path;
      }
    }

    // 2. Merge notes: add new ones, take the backup's copy only if newer.
    final existing = {
      for (final n in (await repository.getNotes()).getOrElse(() => const []))
        n.id: n,
    };
    var added = 0, updated = 0, kept = 0;
    for (final raw in (data['notes'] as List? ?? const [])) {
      NoteEntity note;
      try {
        note = NoteModel.fromJson(Map<String, dynamic>.from(raw as Map));
      } catch (e) {
        LogService().log('Backup: skipped an unreadable note: $e');
        continue;
      }
      note = note.copyWith(blocks: [
        for (final b in note.blocks)
          if (b is ImageBlockEntity && newPaths.containsKey(p.basename(b.imagePath ?? '')))
            b.copyWith(imagePath: newPaths[p.basename(b.imagePath!)])
          else
            b,
      ]);
      final mine = existing[note.id];
      if (mine == null) {
        await repository.addNote(note);
        added++;
      } else if (note.lastModified.isAfter(mine.lastModified)) {
        await repository.updateNote(note);
        updated++;
      } else {
        kept++;
      }
    }

    // 3. Merge folders: add missing ones, combine the notes inside.
    final myGroups = {
      for (final g in (await repository.getGroups()).getOrElse(() => const []))
        g.id: g,
    };
    var folders = 0;
    for (final raw in (data['groups'] as List? ?? const [])) {
      NoteGroupEntity group;
      try {
        group = NoteGroupModel.fromJson(Map<String, dynamic>.from(raw as Map));
      } catch (_) {
        continue;
      }
      final mine = myGroups[group.id];
      final merged = mine == null
          ? group
          : mine.copyWith(noteIds: {...mine.noteIds, ...group.noteIds}.toList());
      if (mine == null || merged.noteIds.length != mine.noteIds.length) {
        await repository.updateGroup(merged);
        folders++;
      }
    }

    return RestoreResult(added: added, updated: updated, kept: kept, folders: folders);
  }

  // ─── Daily backup to a folder (Windows, Linux) ──────────

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  Future<String?> autoBackupFolder() async => (await _box()).get(_autoFolderKey) as String?;

  Future<DateTime?> lastAutoBackup() async =>
      DateTime.tryParse('${(await _box()).get(_lastAutoKey) ?? ''}');

  Future<void> setAutoBackupFolder(String? folder) async {
    final box = await _box();
    if (folder == null) {
      await box.delete(_autoFolderKey);
    } else {
      await box.put(_autoFolderKey, folder);
    }
  }

  /// Writes a backup into the chosen folder now, then keeps only the newest
  /// [keepAutoBackups]. Returns the file written.
  Future<File> backupToFolder(String folder) async {
    final dir = Directory(folder);
    if (!await dir.exists()) {
      throw BackupException("The backup folder doesn't exist anymore: $folder");
    }
    final file = File(p.join(folder, fileName()));
    await file.writeAsBytes(await export(), flush: true);
    await (await _box()).put(_lastAutoKey, DateTime.now().toIso8601String());

    final old = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('codenote-backup-') &&
            f.path.endsWith('.$extension'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(keepAutoBackups)) {
      try {
        await f.delete();
      } catch (_) {}
    }
    return file;
  }

  /// Called at startup: one backup per day if a folder is set. Never throws.
  Future<void> runDailyBackupIfDue() async {
    if (!autoBackupSupported) return;
    try {
      final folder = await autoBackupFolder();
      if (folder == null) return;
      final last = await lastAutoBackup();
      if (last != null && DateTime.now().difference(last) < const Duration(hours: 20)) {
        return;
      }
      final file = await backupToFolder(folder);
      LogService().log('Backup: daily backup saved to ${file.path}');
    } catch (e) {
      LogService().log('Backup: daily backup failed: $e');
    }
  }
}
