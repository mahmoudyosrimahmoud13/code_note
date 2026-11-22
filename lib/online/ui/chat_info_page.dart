import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import 'common.dart';
import 'new_chat_page.dart';
import 'profile_page.dart';

/// Contact info for a direct chat, group info for a group. Pops with
/// 'closed' when the chat is gone for you (left, deleted).
class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage({super.key, required this.chatId});
  final String chatId;

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  ChatStore get _store => ChatStore.instance;
  late final ChatThread _thread = _store.thread(widget.chatId);
  UserPage? _userPage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final chat = await _store.backend.chat(widget.chatId);
      _store.chatUpdated(chat);
      if (!chat.isGroup && chat.otherUser != null) {
        final page = await _store.backend.user(chat.otherUser!.id);
        if (mounted) setState(() => _userPage = page);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Chat? get _chat => _thread.details ?? _store.chatById(widget.chatId);

  Future<void> _closeWith(Future<void> Function() work, {String? done}) async {
    final ok = await attempt(context, work, done: done);
    if (ok && mounted) Navigator.pop(context, 'closed');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _thread]),
      builder: (context, _) {
        final chat = _chat;
        if (chat == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        return chat.isGroup ? _group(context, chat) : _direct(context, chat);
      },
    );
  }

  Widget _muteTile(Chat chat) => SwitchListTile(
        secondary: const Icon(Icons.notifications_off_outlined),
        title: const Text('Mute notifications'),
        value: chat.muted,
        onChanged: (v) => attempt(context, () => _store.setMuted(chat, v)),
      );

  Widget _direct(BuildContext context, Chat chat) {
    final other = chat.otherUser;
    final error = Theme.of(context).colorScheme.error;
    if (other == null) return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    final blocked = _userPage?.blockedByMe ?? chat.blocked == 'me';
    return ProfileView(
      profile: _userPage?.profile ?? other,
      online: _store.isOnline(other),
      lastSeen: _store.lastSeen(other),
      heroTag: 'avatar-${chat.id}',
      commonGroups: _userPage?.commonGroups ?? const [],
      middle: [
        const SectionLabel('this chat'),
        Panel(children: [
          _muteTile(chat),
          _PinnedTile(thread: _thread),
        ]),
      ],
      footer: [
        Panel(children: [
          if (!other.isDeleted)
            ListTile(
              leading: Icon(blocked ? Icons.lock_open_rounded : Icons.block_rounded, color: error),
              title: Text(blocked ? 'Unblock ${other.name}' : 'Block ${other.name}', style: TextStyle(color: error)),
              onTap: () async {
                if (!blocked &&
                    !await confirm(context,
                        title: 'Block ${other.name}?',
                        body: "They won't be able to message you or find you in search.",
                        action: 'Block')) {
                  return;
                }
                if (!context.mounted) return;
                await attempt(context, () async {
                  blocked ? await _store.backend.unblock(other.id) : await _store.backend.block(other.id);
                  await _store.refresh();
                });
                _refresh();
              },
            ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: error),
            title: Text('Delete chat', style: TextStyle(color: error)),
            subtitle: const Text('Removes it and its history from your chats only'),
            onTap: () async {
              if (await confirm(context,
                  title: 'Delete this chat?',
                  body: 'The messages go away for you. ${other.name} still has them. A new message brings the chat back, empty.',
                  action: 'Delete')) {
                if (context.mounted) _closeWith(() => _store.deleteChat(chat));
              }
            },
          ),
        ]),
      ],
    );
  }

  Widget _group(BuildContext context, Chat chat) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final admin = chat.amAdmin;
    final members = [...?chat.members]..sort((a, b) {
        if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
        return a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase());
      });
    final me = _store.myId;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (admin) IconButton(tooltip: 'Edit group', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(chat)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Center(child: Hero(tag: 'avatar-${chat.id}', child: Avatar.chat(chat, size: 104))),
        const SizedBox(height: 14),
        Text(chat.name, textAlign: TextAlign.center, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text('Group · ${members.length} members', textAlign: TextAlign.center, style: TextStyle(color: tokens.subtle)),
        if (chat.description.isNotEmpty) ...[
          const SectionLabel('description'),
          Panel(children: [Padding(padding: const EdgeInsets.all(16), child: Text(chat.description, style: const TextStyle(height: 1.45)))]),
        ],
        const SectionLabel('settings'),
        Panel(children: [
          _muteTile(chat),
          _PinnedTile(thread: _thread),
          if (admin)
            SwitchListTile(
              secondary: const Icon(Icons.campaign_outlined),
              title: const Text('Only admins can send messages'),
              value: chat.adminOnly,
              onChanged: (v) => attempt(context, () async => _store.chatUpdated(await _store.backend.updateGroup(chat.id, adminOnly: v))),
            ),
        ]),
        SectionLabel('${members.length} members',
            trailing: admin
                ? TextButton.icon(
                    onPressed: () => _add(chat),
                    icon: const Icon(Icons.person_add_alt_rounded),
                    label: const Text('Add'),
                  )
                : null),
        Panel(children: [
          for (final m in members)
            ListTile(
              leading: Avatar.profile(m.user, size: 40, online: _store.isOnline(m.user)),
              title: Text(m.user.id == me ? '${m.user.name} (you)' : m.user.name),
              subtitle: Text(
                m.user.id == me ? m.user.handle : lastSeenLabel(_store.isOnline(m.user), _store.lastSeen(m.user)),
                style: TextStyle(fontSize: 12, color: tokens.subtle),
              ),
              trailing: m.isAdmin
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.primary.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                      child: Text('admin', style: monoStyle(context, size: 11, color: color.primary)),
                    )
                  : null,
              onTap: m.user.id == me ? null : () => _memberActions(chat, m),
            ),
        ]),
        const SizedBox(height: 20),
        Panel(children: [
          ListTile(
            leading: Icon(Icons.logout_rounded, color: color.error),
            title: Text('Leave group', style: TextStyle(color: color.error)),
            onTap: () async {
              if (await confirm(context,
                  title: 'Leave ${chat.name}?',
                  body: admin && members.where((m) => m.isAdmin).length == 1 && members.length > 1
                      ? "You're the only admin, so the longest member becomes an admin."
                      : "You won't get its messages anymore.",
                  action: 'Leave')) {
                if (context.mounted) _closeWith(() => _store.leaveGroup(chat));
              }
            },
          ),
          if (admin)
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: color.error),
              title: Text('Delete group for everyone', style: TextStyle(color: color.error)),
              onTap: () async {
                if (await confirm(context,
                    title: 'Delete ${chat.name}?', body: 'The group and all its messages go away for every member.', action: 'Delete')) {
                  if (context.mounted) _closeWith(() => _store.deleteChat(chat));
                }
              },
            ),
        ]),
      ]),
    );
  }

  Future<void> _add(Chat chat) async {
    final picked = await Navigator.push<List<Profile>>(context,
        MaterialPageRoute(builder: (_) => PeoplePicker(exclude: {...?chat.members?.map((m) => m.user.id)})));
    if (picked == null || picked.isEmpty || !mounted) return;
    await attempt(context, () async => _store.chatUpdated(await _store.backend.addMembers(chat.id, [for (final p in picked) p.id])),
        done: picked.length == 1 ? 'Added ${picked.first.name}' : 'Added ${picked.length} people');
  }

  void _memberActions(Chat chat, ChatMember m) {
    final color = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Avatar.profile(m.user, size: 40), title: Text(m.user.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(m.user.handle)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('View profile'),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfilePage(userId: m.user.id)));
            },
          ),
          if (chat.amAdmin) ...[
            ListTile(
              leading: Icon(m.isAdmin ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined),
              title: Text(m.isAdmin ? 'Make a member' : 'Make an admin'),
              onTap: () {
                Navigator.pop(c);
                attempt(context, () async => _store.chatUpdated(await _store.backend.setRole(chat.id, m.user.id, m.isAdmin ? 'member' : 'admin')));
              },
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: color.error),
              title: Text('Remove from group', style: TextStyle(color: color.error)),
              onTap: () async {
                Navigator.pop(c);
                if (await confirm(context, title: 'Remove ${m.user.name}?', body: 'They leave the group and stop getting its messages.', action: 'Remove')) {
                  if (!mounted) return;
                  attempt(context, () async {
                    final updated = await _store.backend.removeMember(chat.id, m.user.id);
                    if (updated != null) _store.chatUpdated(updated);
                  });
                }
              },
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _edit(Chat chat) async {
    final name = TextEditingController(text: chat.name);
    final description = TextEditingController(text: chat.description);
    String? image = chat.imageUrl;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Edit group'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () async {
                  final url = await pickAndUploadPicture(context);
                  if (url != null) set(() => image = url);
                },
                child: Avatar(seed: chat.id, name: chat.name, imageUrl: image, size: 80, group: true),
              ),
              const SizedBox(height: 6),
              Text('Tap to change the picture', style: TextStyle(fontSize: 12, color: c.tokens.subtle)),
              const SizedBox(height: 12),
              TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Name', counterText: '')),
              const SizedBox(height: 10),
              TextField(controller: description, maxLines: 4, minLines: 1, maxLength: 500, decoration: const InputDecoration(labelText: 'Description', counterText: '')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      await attempt(context, () async {
        _store.chatUpdated(await _store.backend.updateGroup(chat.id,
            name: name.text.trim().isEmpty ? null : name.text.trim(),
            description: description.text.trim(),
            imageUrl: image != chat.imageUrl ? (image ?? '') : null));
      });
    }
    name.dispose();
    description.dispose();
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({required this.thread});
  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final n = thread.pinned.length;
    return ListTile(
      leading: const Icon(Icons.push_pin_outlined),
      title: const Text('Pinned messages'),
      trailing: Text('$n', style: monoStyle(context, size: 13, color: context.tokens.subtle)),
      onTap: n == 0
          ? null
          : () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (c) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                    for (final m in thread.pinned)
                      ListTile(
                        leading: const Icon(Icons.push_pin_rounded, size: 18),
                        title: Text(m.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(chatTime(m.createdAt)),
                      ),
                  ]),
                ),
              ),
    );
  }
}
