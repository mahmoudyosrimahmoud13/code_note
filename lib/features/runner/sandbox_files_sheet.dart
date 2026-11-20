import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../constants/themes.dart';
import '../../widgets/brand.dart';
import 'sandbox.dart';

/// Shows the files a note's scripts made. Nothing leaves the sandbox until
/// the person taps "Save a copy" and picks where it goes.
Future<void> showSandboxFiles(BuildContext context, Directory folder, {String title = 'Files'}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SandboxFilesSheet(folder: folder, title: title),
  );
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

/// Lets the person choose where a copy of [file] goes.
Future<bool> saveCopyOf(File file) async {
  final name = p.basename(file.path);
  if (Platform.isAndroid || Platform.isIOS) {
    final result = await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: name));
    return result.status == ShareResultStatus.success;
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return false;
  await file.copy(location.path);
  return true;
}

class _SandboxFilesSheet extends StatefulWidget {
  const _SandboxFilesSheet({required this.folder, required this.title});
  final Directory folder;
  final String title;

  @override
  State<_SandboxFilesSheet> createState() => _SandboxFilesSheetState();
}

class _SandboxFilesSheetState extends State<_SandboxFilesSheet> {
  late Future<List<File>> _files = Sandbox.filesIn(widget.folder);

  void _reload() => setState(() => _files = Sandbox.filesIn(widget.folder));

  Future<void> _save(File f) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await saveCopyOf(f);
      if (ok && !Platform.isAndroid && !Platform.isIOS) {
        messenger.showSnackBar(SnackBar(content: Text('Saved a copy of ${p.basename(f.path)}.'), persist: false));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save: $e"), persist: false));
    }
  }

  Future<void> _delete(File f) async {
    await f.delete();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
              ]),
              Text(
                'These files are in this note\'s sandbox. They stay there until you save a copy somewhere else.',
                style: TextStyle(color: tokens.subtle, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<File>>(
                  future: _files,
                  builder: (context, snap) {
                    final files = snap.data ?? const <File>[];
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (files.isEmpty) {
                      return const TerminalEmptyState(
                        command: 'ls ./sandbox',
                        output: 'no files yet',
                        hint: 'Files your scripts save show up here.',
                      );
                    }
                    return ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final f = files[i];
                        final rel = p.relative(f.path, from: widget.folder.path);
                        final size = f.lengthSync();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(rel, style: monoStyle(context, size: 13), overflow: TextOverflow.ellipsis),
                          subtitle: Text(formatBytes(size)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _delete(f),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _save(f),
                              icon: const Icon(Icons.save_alt_rounded, size: 18),
                              label: const Text('Save a copy'),
                            ),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
