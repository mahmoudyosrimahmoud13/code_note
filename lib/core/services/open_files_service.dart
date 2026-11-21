import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Linux and Windows use the start arguments and the inbox folder.
  static bool get supported => !kIsWeb && (Platform.isLinux || Platform.isWindows);

  /// Android and macOS hand over `codenote://` links (and, on macOS,
  /// opened files) through this channel instead.
  static const _channel = MethodChannel('codenote/links');
  static bool get _usesChannel => !kIsWeb && (Platform.isAndroid || Platform.isMacOS);

  /// A start argument or inbox entry: a CodeNote link, a file:// address
  /// or a file path.
  static String? _target(String arg) {
    final a = arg.trim();
    if (a.isEmpty || a.startsWith('-')) return null;
    if (a.startsWith('codenote:')) return a;
    if (a.startsWith('file://')) {
      try {
        return Uri.parse(a).toFilePath();
      } catch (_) {
        return null;
      }
    }
    final file = File(a);
    return file.existsSync() ? file.absolute.path : null;
  }

  /// Same folder the native runners use: the system temp folder.
  static Directory get inbox => Directory(p.join(Directory.systemTemp.path, 'codenote-open'));

  /// Starts handing files to [open]: the start arguments first, then
  /// whatever arrives in the inbox.
  void start(void Function(String path) open) {
    if (_usesChannel) {
      _open = open;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'link' && call.arguments is String) _deliver(call.arguments as String);
        return null;
      });
      _channel.invokeMethod<Object?>('initialLinks').then((value) {
        final list = value is List ? value : (value is String ? [value] : const []);
        for (final v in list) {
          if (v is String && v.isNotEmpty) _deliver(v);
        }
      }).catchError((Object e) {
        LogService().log('OpenFiles: no link channel: $e');
      });
      return;
    }
    if (!supported) return;
    _open = open;
    for (final arg in launchArgs) {
      final target = _target(arg);
      if (target != null) _deliver(target);
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
    if (_usesChannel) _channel.setMethodCallHandler(null);
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
        final t = _target(target);
        if (t != null) _deliver(t);
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
