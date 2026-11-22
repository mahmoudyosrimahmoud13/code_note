import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

import '../../core/services/log_service.dart';
import '../../features/notes/data/datasources/note_local_data_source.dart';
import '../../features/notes/data/models/note_group_model.dart';
import '../../features/notes/data/models/note_model.dart';
import '../../injection_container.dart' as di;
import '../backend/backend.dart';
import '../models.dart';

/// Keeps notes and folders the same on every device signed in to the same
/// account. Changes made here are queued and sent; changes from other
/// devices come in by revision. The newest change wins.
class NotesSync extends ChangeNotifier {
  NotesSync._();
  static final instance = NotesSync._();

  Backend? _backend;
  Box? _box;
  StreamSubscription? _events;
  Timer? _soon;
  Timer? _every;
  bool _running = false;
  bool _again = false;

  DateTime? lastSynced;
  String? error;
  bool get syncing => _running;
  bool get active => _backend != null;

  /// Changes waiting to be sent.
  int get waiting => (_box?.get('pending') as Map?)?.length ?? 0;

  NoteLocalDataSource get _local => di.sl<NoteLocalDataSource>();

  Future<void> start(Backend backend) async {
    stop();
    _backend = backend;
    _box = await Hive.openBox('notes_sync');
    final me = await _accountId(backend);
    if (_box!.get('account') != me) {
      // A different account on this device: start over and send every
      // local note to it.
      await _box!.putAll({'account': me, 'rev': 0, 'pending': <String, dynamic>{}, 'images': <String, dynamic>{}});
      await _queueEverything();
    }
    final last = _box!.get('last_synced') as String?;
    lastSynced = last == null ? null : DateTime.tryParse(last);
    _events = backend.events.listen((e) {
      if (e is SyncEvent || e is ReconnectedEvent) syncSoon();
    });
    _every = Timer.periodic(const Duration(minutes: 3), (_) => syncNow());
    unawaited(syncNow());
  }

  Future<String> _accountId(Backend b) async {
    try {
      return (await b.me()).id;
    } catch (_) {
      return (_box?.get('account') as String?) ?? '';
    }
  }

  void stop() {
    _events?.cancel();
    _soon?.cancel();
    _every?.cancel();
    _backend = null;
    notifyListeners();
  }

  /// Forget sync state (signed out: the next account starts fresh).
  Future<void> reset() async {
    stop();
    final box = _box ?? await Hive.openBox('notes_sync');
    await box.clear();
  }

  Future<void> _queueEverything() async {
    final pending = <String, dynamic>{};
    for (final n in await _local.getLastNotes()) {
      pending['note:${n.id}'] = {'deleted': false};
    }
    for (final g in await _local.getLastGroups()) {
      pending['group:${g.id}'] = {'deleted': false};
    }
    await _box!.put('pending', pending);
  }

  /// A note or folder changed on this device.
  Future<void> changed(String kind, String id, {bool deleted = false}) async {
    final box = _box ?? await Hive.openBox('notes_sync');
    _box = box;
    final pending = Map<String, dynamic>.from((box.get('pending') as Map?) ?? const {});
    pending['$kind:$id'] = {'deleted': deleted, if (deleted) 'at': DateTime.now().toUtc().toIso8601String()};
    await box.put('pending', pending);
    syncSoon();
    notifyListeners();
  }

  void syncSoon() {
    if (_backend == null) return;
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    if (_backend == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    notifyListeners();
    try {
      do {
        _again = false;
        await _push();
        await _pull();
      } while (_again);
      error = null;
      lastSynced = DateTime.now();
      await _box?.put('last_synced', lastSynced!.toIso8601String());
    } on ApiError catch (e) {
      error = e.offline ? null : e.message; // offline: try again later, quietly
    } catch (e) {
      error = 'Sync stopped: $e';
      LogService().log('Sync: $e');
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  // ─── Send ──────────────────────────────────────────────

  Future<void> _push() async {
    final box = _box!;
    final pending = Map<String, dynamic>.from((box.get('pending') as Map?) ?? const {});
    if (pending.isEmpty) return;
    final keys = pending.keys.toList();
    for (var start = 0; start < keys.length; start += 100) {
      final batch = keys.sublist(start, start + 100 > keys.length ? keys.length : start + 100);
      final items = <Map<String, dynamic>>[];
      final sentKeys = <String>[];
      for (final key in batch) {
        final item = await _itemFor(key, Map<String, dynamic>.from(pending[key] as Map));
        if (item != null) items.add(item);
        sentKeys.add(key);
      }
      if (items.isNotEmpty) {
        final result = await _backend!.syncPush(items);
        // The cloud had a newer copy: take it.
        for (final c in result.conflicts) {
          await _applyRemote(c);
        }
      }
      final now = Map<String, dynamic>.from((box.get('pending') as Map?) ?? const {});
      for (final k in sentKeys) {
        // Only drop it if it didn't change again while sending.
        if (now[k] is Map && (now[k] as Map)['deleted'] == (pending[k] as Map)['deleted']) now.remove(k);
      }
      await box.put('pending', now);
    }
  }

  Future<Map<String, dynamic>?> _itemFor(String key, Map<String, dynamic> info) async {
    final sep = key.indexOf(':');
    final kind = key.substring(0, sep);
    final id = key.substring(sep + 1);
    if (info['deleted'] == true) {
      return {'kind': kind, 'id': id, 'deleted': true, 'modified_at': info['at'] ?? DateTime.now().toUtc().toIso8601String()};
    }
    if (kind == 'note') {
      final note = await _local.getNote(id);
      if (note == null) return null;
      final json = note.toJson()
        ..remove('isDirty')
        ..remove('lastSyncedAt');
      json['blocks'] = [for (final b in (json['blocks'] as List)) await _withUploadedImage(Map<String, dynamic>.from(b as Map))];
      return {'kind': 'note', 'id': id, 'data': json, 'modified_at': note.lastModified.toUtc().toIso8601String()};
    }
    final groups = await _local.getLastGroups();
    final group = groups.where((g) => g.id == id).firstOrNull;
    if (group == null) return null;
    return {'kind': 'group', 'id': id, 'data': group.toJson(), 'modified_at': group.lastModified.toUtc().toIso8601String()};
  }

  /// Pictures in notes are files on this device: upload each once and send
  /// its web address instead.
  Future<Map<String, dynamic>> _withUploadedImage(Map<String, dynamic> block) async {
    final path = block['imagePath'] as String?;
    if (path == null || path.isEmpty || path.startsWith('http') || kIsWeb) return block;
    final images = Map<String, dynamic>.from((_box!.get('images') as Map?) ?? const {});
    var url = images[path] as String?;
    if (url == null) {
      final file = File(path);
      if (!await file.exists()) return block;
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final type = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' => 'image/heic',
        _ => 'image/jpeg',
      };
      try {
        url = await _backend!.uploadImage(await file.readAsBytes(), contentType: type, extension: ext.isEmpty ? 'jpg' : ext);
      } on ApiError catch (e) {
        if (e.offline) rethrow;
        return block; // a picture the server refuses: send the note without it
      }
      images[path] = url;
      await _box!.put('images', images);
    }
    return {...block, 'imagePath': url};
  }

  // ─── Receive ───────────────────────────────────────────

  Future<void> _pull() async {
    final box = _box!;
    var rev = (box.get('rev') as int?) ?? 0;
    for (var i = 0; i < 50; i++) {
      final page = await _backend!.syncPull(rev);
      for (final item in page.items) {
        await _applyRemote(item);
      }
      rev = page.rev;
      await box.put('rev', rev);
      if (page.items.isEmpty || rev >= page.latest) break;
    }
  }

  Future<void> _applyRemote(SyncItem item) async {
    // My own unsent change to the same item wins over what's coming in
    // (it's newer; it goes up next).
    final pending = (_box!.get('pending') as Map?) ?? const {};
    if (pending.containsKey('${item.kind}:${item.id}')) return;
    try {
      if (item.kind == 'note') {
        if (item.deleted) {
          await _local.deleteNote(item.id);
        } else if (item.data != null) {
          final remote = NoteModel.fromJson({...item.data!, 'isDirty': false});
          final local = await _local.getNote(item.id);
          if (local == null || !local.lastModified.isAfter(remote.lastModified)) {
            await _local.saveNote(remote.copyWith(lastSyncedAt: DateTime.now()));
          }
        }
      } else if (item.kind == 'group') {
        if (item.deleted) {
          await _local.deleteGroup(item.id);
        } else if (item.data != null) {
          await _local.saveGroup(NoteGroupModel.fromJson(item.data!));
        }
      }
    } catch (e) {
      LogService().log('Sync: skipped ${item.kind} ${item.id}: $e');
    }
  }
}
