import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import '../online_config.dart';
import '../online_service.dart';
import '../sync/notes_sync.dart';
import 'admin_page.dart';
import 'auth_pages.dart';
import 'common.dart';
import 'new_chat_page.dart';

/// Your account: profile, sync, privacy, sign out.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([OnlineService.instance, NotesSync.instance]),
      builder: (context, _) {
        final online = OnlineService.instance;
        final me = online.me;
        final color = Theme.of(context).colorScheme;
        final tokens = context.tokens;
        if (me == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Account')),
            body: EmptyState(
              icon: Icons.account_circle_outlined,
              title: 'Not signed in',
              body: 'Sign in to chat and to keep your notes on all your devices.',
              action: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (c) => online.stage == OnlineStage.needsServer
                          ? ServerAddressPage(onBack: () => Navigator.pop(c))
                          : const AuthPage()),
                ),
                child: Text(online.stage == OnlineStage.needsServer ? 'Connect to a server' : 'Sign in'),
              ),
            ),
          );
        }
        final sync = NotesSync.instance;
        return Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            const SizedBox(height: 8),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(60),
                onTap: () => _changePicture(context),
                child: Stack(children: [
                  Avatar.profile(me, size: 104),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: CircleAvatar(radius: 17, backgroundColor: color.primary,
                        child: Icon(Icons.photo_camera_rounded, size: 17, color: color.onPrimary)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(me.name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(me.handle, textAlign: TextAlign.center, style: monoStyle(context, size: 13, color: tokens.subtle)),
            const SectionLabel('profile'),
            Panel(children: [
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Name'),
                subtitle: Text(me.name),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editField(context, 'Name', me.name, (v) => online.backend.updateProfile(name: v)),
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email_rounded),
                title: const Text('Username'),
                subtitle: Text(me.handle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editUsername(context, me),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About'),
                subtitle: Text(me.about.isEmpty ? 'A line about you, your stack, what you build' : me.about,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editField(context, 'About', me.about, (v) => online.backend.updateProfile(about: v), maxLines: 3, maxLength: 300),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: const Text('My QR code'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQrPage())),
              ),
            ]),
            const SectionLabel('notes sync'),
            Panel(children: [
              ListTile(
                leading: sync.syncing
                    ? const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)))
                    : Icon(sync.error == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                        color: sync.error == null ? tokens.success : color.error),
                title: Text(sync.syncing
                    ? 'Syncing…'
                    : sync.error ?? (sync.lastSynced == null ? 'Not synced yet' : 'Synced ${chatTime(sync.lastSynced!)}')),
                subtitle: Text(sync.waiting > 0
                    ? '${sync.waiting} ${sync.waiting == 1 ? 'change' : 'changes'} waiting to be sent'
                    : 'Your notes and folders are the same on every device you sign in on'),
                trailing: TextButton(onPressed: sync.syncing ? null : sync.syncNow, child: const Text('Sync now')),
              ),
            ]),
            const SectionLabel('account'),
            Panel(children: [
              ListTile(
                leading: const Icon(Icons.mail_outline_rounded),
                title: const Text('Email'),
                subtitle: Text(me.email ?? ''),
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _changePassword(context),
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: const Text('Blocked people'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _BlockedPage())),
              ),
              if (OnlineConfig.isFastApi)
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(online.serverName),
                  subtitle: Text(online.serverUrl ?? '', style: monoStyle(context, size: 11.5, color: tokens.subtle)),
                  trailing: TextButton(
                    onPressed: () async {
                      if (await confirm(context,
                          title: 'Use another server?',
                          body: "You'll be signed out here. Your notes on this device stay.",
                          action: 'Change server',
                          danger: false)) {
                        await online.forgetServer();
                        if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    },
                    child: const Text('Change'),
                  ),
                )
              else
                const ListTile(leading: Icon(Icons.bolt_rounded), title: Text('Supabase'), subtitle: Text('Chats and sync run on Supabase')),
            ]),
            if (me.isAdmin) ...[
              const SectionLabel('admin'),
              Panel(children: [
                ListTile(
                  leading: Icon(Icons.admin_panel_settings_outlined, color: color.primary),
                  title: const Text('Admin dashboard'),
                  subtitle: const Text('People, sign-up, announcements'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage())),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            Panel(children: [
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign out'),
                subtitle: const Text('Your notes stay on this device'),
                onTap: () async {
                  if (await confirm(context, title: 'Sign out?', body: 'Chats stop here until you sign in again. Your notes stay on this device.', action: 'Sign out', danger: false)) {
                    await online.signOut();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: color.error),
                title: Text('Delete account', style: TextStyle(color: color.error)),
                subtitle: const Text('Your messages stay in chats as "Deleted account"'),
                onTap: () => _deleteAccount(context),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Future<void> _changePicture(BuildContext context) async {
    final url = await pickAndUploadPicture(context);
    if (url == null || !context.mounted) return;
    await attempt(context, () async => OnlineService.instance.updateMe(await OnlineService.instance.backend.updateProfile(avatarUrl: url)));
  }

  Future<void> _editField(BuildContext context, String label, String value, Future<Profile> Function(String) save,
      {int maxLines = 1, int maxLength = 80}) async {
    final c = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(label),
        content: SizedBox(
          width: 380,
          child: TextField(controller: c, autofocus: true, maxLines: maxLines, maxLength: maxLength),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (result == null || result == value || !context.mounted) return;
    await attempt(context, () async => OnlineService.instance.updateMe(await save(result)));
  }

  Future<void> _editUsername(BuildContext context, Profile me) async {
    final saved = await showDialog<Profile>(context: context, builder: (_) => _UsernameDialog(current: me.username ?? ''));
    if (saved != null) await OnlineService.instance.updateMe(saved);
  }

  Future<void> _changePassword(BuildContext context) async {
    final old = TextEditingController();
    final fresh = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Change password'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: old, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 10),
            TextField(controller: fresh, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Change')),
        ],
      ),
    );
    if (go == true && context.mounted) {
      if (fresh.text.length < 8) {
        showSnack(context, 'Passwords need at least 8 characters.', error: true);
      } else {
        await attempt(context, () => OnlineService.instance.backend.changePassword(old.text, fresh.text),
            done: 'Password changed. Other devices are signed out.');
      }
    }
    old.dispose();
    fresh.dispose();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final sure = await confirm(context,
        title: 'Delete your account?',
        body: 'This removes your profile and the notes kept in the cloud, and takes you out of every group. '
            'Notes on this device stay. This can\'t be undone.',
        action: 'Delete my account');
    if (!sure || !context.mounted) return;
    final ok = await attempt(context, OnlineService.instance.deleteAccount, done: 'Your account was deleted.');
    if (ok && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.current});
  final String current;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late final _c = TextEditingController(text: widget.current);
  bool? _free;
  bool _busy = false;
  String? _error;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _t?.cancel();
    setState(() {
      _free = null;
      _error = null;
    });
    final u = v.trim().toLowerCase().replaceFirst('@', '');
    if (u == widget.current) return;
    if (!RegExp(r'^[a-z0-9_.]{3,24}$').hasMatch(u)) {
      setState(() => _error = '3 to 24 characters: letters, numbers, _ and .');
      return;
    }
    _t = Timer(const Duration(milliseconds: 400), () async {
      try {
        final free = await OnlineService.instance.backend.usernameAvailable(u);
        if (mounted) setState(() => _free = free);
      } catch (_) {}
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final p = await OnlineService.instance.backend.updateProfile(username: _c.text.trim().toLowerCase().replaceFirst('@', ''));
      if (mounted) Navigator.pop(context, p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Username'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _c,
          autofocus: true,
          onChanged: _changed,
          decoration: InputDecoration(
            prefixText: '@',
            errorText: _error ?? (_free == false ? 'That username is taken' : null),
            helperText: _free == true ? 'Available' : 'How people find you',
            suffixIcon: _free == null ? null : Icon(_free! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _free! ? tokens.success : color.error),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy || _free != true ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

class _BlockedPage extends StatefulWidget {
  const _BlockedPage();

  @override
  State<_BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<_BlockedPage> {
  List<Profile>? _people;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await OnlineService.instance.backend.blockedUsers();
      if (mounted) setState(() => _people = p);
    } catch (e) {
      if (mounted) {
        setState(() => _people = const []);
        showSnack(context, e, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked people')),
      body: people == null
          ? const Center(child: CircularProgressIndicator())
          : people.isEmpty
              ? const EmptyState(icon: Icons.block_rounded, title: "You haven't blocked anyone")
              : ListView(children: [
                  for (final p in people)
                    ListTile(
                      leading: Avatar.profile(p, size: 40),
                      title: Text(p.name),
                      subtitle: Text(p.handle),
                      trailing: TextButton(
                        onPressed: () async {
                          final ok = await attempt(context, () => OnlineService.instance.backend.unblock(p.id), done: 'Unblocked ${p.name}');
                          if (ok) {
                            _load();
                            ChatStore.instance.refresh();
                          }
                        },
                        child: const Text('Unblock'),
                      ),
                    ),
                ]),
    );
  }
}
