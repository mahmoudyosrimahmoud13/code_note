import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How strongly scripts are kept away from the rest of the device.
enum SandboxLevel {
  /// The operating system locks the app in (Android, macOS App Sandbox).
  system,

  /// Linux with bubblewrap: scripts only see their own folder.
  bubblewrap,

  /// Only a private folder and private settings. A script could still reach
  /// other files if it really tried, so this needs the person's OK.
  folderOnly,

  /// Running code isn't possible here (iOS, web).
  unavailable,
}

/// Everything about where scripts run and what they can see.
///
/// Each note gets its own sandbox folder. Scripts start there, their home
/// folder and temp folder point there, and what they download stays there
/// until the person chooses "Save a copy".
class Sandbox {
  Sandbox._();
  static final Sandbox instance = Sandbox._();

  static const _boxName = 'appBox';
  static const _allowKey = 'ALLOW_FOLDER_SANDBOX';

  Directory? _root;
  String? _bwrap;
  bool _checked = false;

  /// Platforms where code can run at all.
  static bool get supported =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS || Platform.isAndroid);

  Future<Directory> root() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'sandbox'));
    await dir.create(recursive: true);
    return _root = dir;
  }

  /// Downloaded runtimes (Python, BusyBox) and CodeNote's Python packages.
  Future<Directory> runtimesDir() async {
    final dir = Directory(p.join((await root()).path, 'runtimes'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Which sandbox a note uses: notes in the same folder share one, so a
  /// backend in one note and a page in another see the same files and
  /// can run together. A note outside any folder gets its own.
  static String keyFor({required String noteId, String? folderId}) =>
      folderId != null ? 'folder-$folderId' : 'note-$noteId';

  /// The sandbox folder for [key] (see [keyFor]).
  Future<Directory> space(String key) async {
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dir = Directory(p.join((await root()).path, 'spaces', safe));
    await dir.create(recursive: true);
    return dir;
  }

  /// The folder the Terminal starts in.
  Future<Directory> terminalHome() async {
    final dir = Directory(p.join((await root()).path, 'terminal'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<SandboxLevel> level() async {
    if (!supported) return SandboxLevel.unavailable;
    if (Platform.isAndroid || Platform.isMacOS) return SandboxLevel.system;
    if (Platform.isLinux && await bubblewrap() != null) return SandboxLevel.bubblewrap;
    return SandboxLevel.folderOnly;
  }

  /// Path to bubblewrap on Linux, or null if it isn't installed.
  Future<String?> bubblewrap() async {
    if (_checked) return _bwrap;
    _checked = true;
    if (!Platform.isLinux) return null;
    for (final candidate in ['/usr/bin/bwrap', '/bin/bwrap', '/usr/local/bin/bwrap']) {
      if (await File(candidate).exists()) return _bwrap = candidate;
    }
    return null;
  }

  /// Checks bubblewrap again (after the person installed it).
  void recheck() => _checked = false;

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  /// For [SandboxLevel.folderOnly]: the person agreed to run scripts with
  /// only a private folder as protection.
  Future<bool> folderSandboxAllowed() async => (await _box()).get(_allowKey) == true;
  Future<void> setFolderSandboxAllowed(bool allowed) async => (await _box()).put(_allowKey, allowed);

  /// True when scripts may run now. Null means it needs the person's OK.
  Future<bool?> canRun() async {
    switch (await level()) {
      case SandboxLevel.system:
      case SandboxLevel.bubblewrap:
        return true;
      case SandboxLevel.folderOnly:
        return await folderSandboxAllowed() ? true : null;
      case SandboxLevel.unavailable:
        return false;
    }
  }

  /// Private environment for a run: home, temp and caches all inside the
  /// sandbox, and [extraPath] first on PATH.
  Future<Map<String, String>> environment(Directory home, {List<String> extraPath = const []}) async {
    final rootDir = (await root()).path;
    final tmp = Directory(p.join(home.path, '.tmp'))..createSync(recursive: true);
    final sep = Platform.isWindows ? ';' : ':';
    final systemPath = Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '';
    final env = <String, String>{
      'HOME': home.path,
      'TMPDIR': tmp.path,
      'TEMP': tmp.path,
      'TMP': tmp.path,
      'XDG_CACHE_HOME': p.join(rootDir, 'cache'),
      'XDG_CONFIG_HOME': p.join(home.path, '.config'),
      'XDG_DATA_HOME': p.join(home.path, '.local', 'share'),
      'PIP_CACHE_DIR': p.join(rootDir, 'cache', 'pip'),
      'PYTHONUSERBASE': p.join(home.path, '.local'),
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUNBUFFERED': '1',
      'PIP_DISABLE_PIP_VERSION_CHECK': '1',
      'CODENOTE_SANDBOX': home.path,
      'PATH': [...extraPath, systemPath].where((e) => e.isNotEmpty).join(sep),
    };
    if (Platform.isWindows) {
      env['USERPROFILE'] = home.path;
      env['APPDATA'] = p.join(home.path, 'AppData', 'Roaming');
      env['LOCALAPPDATA'] = p.join(home.path, 'AppData', 'Local');
      for (final keep in ['SystemRoot', 'SystemDrive', 'ComSpec', 'PATHEXT', 'WINDIR', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE']) {
        final v = Platform.environment[keep];
        if (v != null) env[keep] = v;
      }
    } else {
      env['LANG'] = Platform.environment['LANG'] ?? 'C.UTF-8';
      env['TERM'] = 'dumb';
    }
    return env;
  }

  /// The command to start: [executable] wrapped in bubblewrap on Linux.
  ///
  /// Under bubblewrap the script sees the system read-only, an empty /home,
  /// /media and /mnt, and only [writable] (its sandbox folder) can be
  /// changed. [readOnly] (runtimes) is visible but can't be changed, and
  /// [extraWritable] is for package installs into CodeNote's Python.
  /// Internet access stays on so pip and downloads work.
  Future<(String, List<String>)> command(
    String executable,
    List<String> args, {
    required Directory writable,
    List<String> readOnly = const [],
    List<String> extraWritable = const [],
  }) async {
    final bwrap = await bubblewrap();
    if (bwrap == null) return (executable, args);
    final rootDir = (await root()).path;
    await Directory(p.join(rootDir, 'cache')).create(recursive: true);
    return (bwrap, [
      '--ro-bind', '/', '/',
      '--dev', '/dev',
      '--proc', '/proc',
      '--tmpfs', '/tmp',
      '--tmpfs', '/home',
      '--tmpfs', '/root',
      '--tmpfs', '/media',
      '--tmpfs', '/mnt',
      '--tmpfs', '/run/media',
      // Shared caches and runtimes live in the sandbox root.
      '--ro-bind', rootDir, rootDir,
      for (final dir in readOnly) ...['--ro-bind', dir, dir],
      '--bind', p.join(rootDir, 'cache'), p.join(rootDir, 'cache'),
      for (final dir in extraWritable) ...['--bind', dir, dir],
      '--bind', writable.path, writable.path,
      '--chdir', writable.path,
      '--unshare-pid',
      '--unshare-ipc',
      '--unshare-uts',
      '--share-net',
      '--die-with-parent',
      '--new-session',
      '--',
      executable,
      ...args,
    ]);
  }

  /// Folder sizes and file lists for the Files sheet.
  static Future<List<File>> filesIn(Directory dir) async {
    if (!await dir.exists()) return const [];
    final files = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: dir.path);
      // Hide CodeNote's own helper files and caches.
      if (rel.split(p.separator).any((part) => part.startsWith('.'))) continue;
      files.add(e);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Deletes every sandbox folder except the downloaded runtimes.
  Future<void> clearFiles() async {
    final rootDir = await root();
    for (final name in ['spaces', 'terminal', 'cache']) {
      final d = Directory(p.join(rootDir.path, name));
      if (await d.exists()) await d.delete(recursive: true);
    }
  }
}
