import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

import '../runner/sandbox.dart';

/// A workspace: a folder of files opened in CodeNote, like a small IDE.
/// It is a normal CodeNote folder, so its notes share one sandbox with the
/// files: a notebook in it can read `sales.csv` by name. The files are a
/// copy; the original folder only changes when you press Save back.
class WorkspaceInfo {
  WorkspaceInfo({required this.groupId, required this.name, this.source, Map<String, String>? noteFiles})
      : noteFiles = noteFiles ?? {};

  final String groupId;
  final String name;

  /// The folder it was opened from (computers), for Save back.
  final String? source;

  /// Note id → the file it was opened from (relative path).
  final Map<String, String> noteFiles;

  String get spaceKey => Sandbox.keyFor(noteId: '', folderId: groupId);

  Map<String, Object?> toJson() => {'groupId': groupId, 'name': name, 'source': source, 'noteFiles': noteFiles};

  static WorkspaceInfo fromJson(Map<String, dynamic> m) => WorkspaceInfo(
        groupId: '${m['groupId']}',
        name: '${m['name']}',
        source: m['source'] as String?,
        noteFiles: (m['noteFiles'] as Map?)?.map((k, v) => MapEntry('$k', '$v')),
      );
}

class CopyResult {
  CopyResult(this.files, this.bytes, this.skipped);
  final int files;
  final int bytes;
  final int skipped;
}

class WorkspaceService {
  WorkspaceService._();
  static final WorkspaceService instance = WorkspaceService._();

  static const _boxName = 'workspaces';

  /// Folders that are big and never needed in a workspace.
  static const skipDirs = {
    '.git', 'node_modules', '__pycache__', '.venv', 'venv', 'env', '.idea', '.vscode', '.dart_tool',
    'build', '.gradle', '.mypy_cache', '.pytest_cache', '.ipynb_checkpoints', '.tox', 'dist', '.next',
  };
  static const maxFiles = 3000;
  static const maxBytes = 300 * 1024 * 1024;

  /// File types the data viewer opens.
  static const dataExtensions = {'.csv', '.tsv', '.json', '.jsonl', '.xlsx', '.xls', '.parquet'};

  Future<Box> _box() => Hive.isBoxOpen(_boxName) ? Future.value(Hive.box(_boxName)) : Hive.openBox(_boxName);

  Future<WorkspaceInfo?> get(String groupId) async {
    final raw = (await _box()).get(groupId);
    if (raw is! String) return null;
    try {
      return WorkspaceInfo.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(WorkspaceInfo info) async => (await _box()).put(info.groupId, json.encode(info.toJson()));

  Future<void> forget(String groupId) async => (await _box()).delete(groupId);

  Future<Directory> folder(WorkspaceInfo info) => Sandbox.instance.space(info.spaceKey);

  /// Copies a folder into the workspace, skipping caches and git, with a
  /// limit so a huge folder can't fill the phone.
  Future<CopyResult> copyFolder(String from, Directory to, {void Function(int files)? onProgress}) async {
    var files = 0, bytes = 0, skipped = 0;
    final root = Directory(from);
    final stack = [root];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (skipDirs.contains(name)) {
            skipped++;
          } else {
            stack.add(e);
          }
          continue;
        }
        if (e is! File) continue;
        final size = await e.length();
        if (files >= maxFiles || bytes + size > maxBytes) {
          skipped++;
          continue;
        }
        final target = File(p.join(to.path, p.relative(e.path, from: root.path)));
        await target.parent.create(recursive: true);
        await e.copy(target.path);
        files++;
        bytes += size;
        if (files % 25 == 0) onProgress?.call(files);
      }
    }
    return CopyResult(files, bytes, skipped);
  }

  /// Copies picked files (phones) into the workspace.
  Future<void> copyFiles(List<String> paths, List<String> names, Directory to) async {
    for (var i = 0; i < paths.length; i++) {
      final target = File(p.join(to.path, names[i]));
      await File(paths[i]).copy(target.path);
    }
  }

  /// Files, folders first, without hidden ones (CodeNote's own .codenote).
  static Future<List<FileSystemEntity>> list(Directory dir) async {
    if (!await dir.exists()) return const [];
    final entries = (await dir.list(followLinks: false).toList())
        .where((e) => !p.basename(e.path).startsWith('.'))
        .toList();
    entries.sort((a, b) {
      final ad = a is Directory, bd = b is Directory;
      if (ad != bd) return ad ? -1 : 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return entries;
  }

  /// Files that are new or changed compared with the original folder.
  Future<List<String>> changedFiles(WorkspaceInfo info) async {
    final source = info.source;
    if (source == null) return const [];
    final root = await folder(info);
    final changed = <String>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root.path);
      if (rel.split(p.separator).any((s) => s.startsWith('.'))) continue;
      final original = File(p.join(source, rel));
      if (!await original.exists()) {
        changed.add(rel);
        continue;
      }
      final a = await e.length(), b = await original.length();
      if (a != b) {
        changed.add(rel);
      } else if (a < 8 * 1024 * 1024 && !_same(await e.readAsBytes(), await original.readAsBytes())) {
        changed.add(rel);
      }
    }
    changed.sort();
    return changed;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Copies [files] back into the original folder.
  Future<void> saveBack(WorkspaceInfo info, List<String> files) async {
    final source = info.source;
    if (source == null) return;
    final root = await folder(info);
    for (final rel in files) {
      final target = File(p.join(source, rel));
      await target.parent.create(recursive: true);
      await File(p.join(root.path, rel)).copy(target.path);
    }
  }
}
