import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'log_service.dart';

/// Files the system asks CodeNote to open on desktop: double-clicking a
/// `.codenote` file, or "Open with CodeNote".
///
/// The first launch gets them as start arguments. When CodeNote is already
/// running, the new copy (which closes right away, only one CodeNote runs
/// at a time) drops each path as a small file into [inbox], and the running
/// app picks it up here. The Linux and Windows runners write that inbox.
class OpenFilesService {
  OpenFilesService._();
  static final OpenFilesService instance = OpenFilesService._();

  /// Start arguments from main().
  List<String> launchArgs = const [];

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _poll;
  void Function(String path)? _open;
  final _seen = <String>{};

  static bool get supported => !kIsWeb && (Platform.isLinux || Platform.isWindows);

  /// Same folder the native runners use: the system temp folder.
  static Directory get inbox => Directory(p.join(Directory.systemTemp.path, 'codenote-open'));

  /// Starts handing files to [open]: the start arguments first, then
  /// whatever arrives in the inbox.
  void start(void Function(String path) open) {
    if (!supported) return;
    _open = open;
    for (final arg in launchArgs) {
      if (arg.startsWith('-')) continue;
      final file = File(arg);
      if (file.existsSync()) _deliver(file.absolute.path);
    }
    launchArgs = const [];
    try {
      inbox.createSync(recursive: true);
      _drain();
      _watch = inbox.watch(events: FileSystemEvent.create | FileSystemEvent.modify).listen((_) {
        // The writer may still be busy: read a moment later.
        Timer(const Duration(milliseconds: 150), _drain);
      });
    } catch (e) {
      LogService().log('OpenFiles: watching the inbox failed: $e');
    }
    // Some file systems don't report changes; a slow poll is the backup.
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _drain());
  }

  void stop() {
    _watch?.cancel();
    _poll?.cancel();
    _watch = null;
    _poll = null;
    _open = null;
  }

  void _drain() {
    try {
      if (!inbox.existsSync()) return;
      final entries = inbox.listSync().whereType<File>().where((f) => f.path.endsWith('.path')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final entry in entries) {
        String target;
        try {
          target = entry.readAsStringSync().trim();
          entry.deleteSync();
        } catch (_) {
          continue; // still being written, next round
        }
        if (target.isNotEmpty && File(target).existsSync()) _deliver(target);
      }
    } catch (e) {
      LogService().log('OpenFiles: reading the inbox failed: $e');
    }
  }

  void _deliver(String path) {
    // The same file twice within a few seconds is one double-click.
    if (!_seen.add(path)) return;
    Timer(const Duration(seconds: 5), () => _seen.remove(path));
    _open?.call(path);
  }
}
