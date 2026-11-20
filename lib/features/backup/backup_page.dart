import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/themes.dart';
import '../../core/util/note_share_helper.dart';
import '../../injection_container.dart' as di;
import 'backup_service.dart';

/// Settings > Backup: save everything to a file, restore it, and (on
/// Windows and Linux) keep a daily backup in a folder.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final BackupService _service = di.sl<BackupService>();
  bool _busy = false;
  String? _folder;
  DateTime? _lastAuto;

  @override
  void initState() {
    super.initState();
    _loadAuto();
  }

  Future<void> _loadAuto() async {
    final folder = await _service.autoBackupFolder();
    final last = await _service.lastAutoBackup();
    if (mounted) {
      setState(() {
        _folder = folder;
        _lastAuto = last;
      });
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('Something went wrong: $e', error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export() => _run(() async {
        final bytes = await _service.export();
        final saved = await NoteShareHelper.saveOrShareBytes(
          bytes,
          fileName: _service.fileName(),
          mimeType: 'application/json',
          typeLabel: 'CodeNote backup',
          shareText: 'CodeNote backup',
        );
        if (saved != null) _toast('Backup saved to $saved');
      });

  Future<void> _import() => _run(() async {
        final file = await openFile(acceptedTypeGroups: const [
          XTypeGroup(
            label: 'CodeNote backup',
            extensions: ['codenote', 'json'],
            mimeTypes: ['application/json', 'application/octet-stream'],
            uniformTypeIdentifiers: ['public.json', 'public.data'],
          ),
        ]);
        if (file == null) return;
        final result = await _service.restore(await file.readAsBytes());
        _toast(result.summary);
      });

  Future<void> _chooseFolder() => _run(() async {
        final folder = await getDirectoryPath(confirmButtonText: 'Use this folder');
        if (folder == null) return;
        await _service.setAutoBackupFolder(folder);
        final file = await _service.backupToFolder(folder);
        await _loadAuto();
        _toast('Daily backup is on. First backup: ${file.path}');
      });

  Future<void> _turnOffAuto() => _run(() async {
        await _service.setAutoBackupFolder(null);
        await _loadAuto();
        _toast('Daily backup is off. Old backups in the folder were kept.');
      });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;

    Widget card({required IconData icon, required String title, required String body, required Widget action}) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppBrand.radius),
          border: Border.all(color: color.outlineVariant.withAlpha(160)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color.primary),
              const SizedBox(width: 10),
              Text(title, style: text.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(body, style: text.bodyMedium?.copyWith(color: color.onSurfaceVariant)),
            const SizedBox(height: 14),
            action,
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              card(
                icon: Icons.save_alt_rounded,
                title: 'Back up now',
                body: 'Saves every note, folder and image into one .codenote file. '
                    'Keep it somewhere safe, like Google Drive or a USB stick.',
                action: FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(Platform.isAndroid || Platform.isIOS
                      ? 'Create and share backup'
                      : 'Save backup file'),
                ),
              ),
              card(
                icon: Icons.settings_backup_restore_rounded,
                title: 'Restore',
                body: 'Adds the notes from a backup file. Nothing is deleted: '
                    'if a note exists on both sides, the newer version is kept.',
                action: OutlinedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Restore from file'),
                ),
              ),
              if (BackupService.autoBackupSupported)
                card(
                  icon: Icons.schedule_rounded,
                  title: 'Daily backup to a folder',
                  body: _folder == null
                      ? 'Pick a folder (Dropbox, Google Drive, Syncthing, a Git repo) and '
                          'CodeNote saves a backup there once a day, keeping the last '
                          '${BackupService.keepAutoBackups}. That folder can sync your notes '
                          'to other computers.'
                      : 'On. Saving to:\n$_folder\n'
                          'Last backup: ${_lastAuto == null ? 'not yet' : DateFormat.yMMMd().add_jm().format(_lastAuto!)}',
                  action: Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _chooseFolder,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(_folder == null ? 'Choose folder' : 'Change folder'),
                    ),
                    if (_folder != null) ...[
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                  final f = await _service.backupToFolder(_folder!);
                                  await _loadAuto();
                                  _toast('Saved ${f.path}');
                                }),
                        child: const Text('Back up now'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _turnOffAuto,
                        child: const Text('Turn off'),
                      ),
                    ],
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '// backups include your notes and images, not your settings or AI key.',
                  style: monoStyle(context, size: 11, color: tokens.subtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
