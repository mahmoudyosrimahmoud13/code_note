import 'package:flutter/material.dart';

import '../../constants/themes.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import '../online_service.dart';
import 'account_page.dart';
import 'auth_pages.dart';
import 'common.dart';
import 'conversation_page.dart';
import 'new_chat_page.dart';

enum _Filter { all, unread, groups }

/// Your chats. On wide screens the open conversation sits next to the list.
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, this.openChatId});
  final String? openChatId;

  /// Opens the chat list (and a chat, if given) from anywhere.
  static Future<void> open(BuildContext context, {String? chatId}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatsPage(openChatId: chatId)));

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String? _selected;
  bool _searching = false;

  ChatStore get _store => ChatStore.instance;

  @override
  void initState() {
    super.initState();
    _selected = widget.openChatId;
    if (_store.active && !_store.loaded) _store.refresh();
    if (widget.openChatId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_wide(context)) _openChat(widget.openChatId!);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _wide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

  void _openChat(String id) {
    if (_wide(context)) {
      setState(() => _selected = id);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationPage(chatId: id)));
    }
  }

  Future<void> _newChat() async {
    final chatId = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const NewChatPage()));
    if (chatId != null && mounted) _openChat(chatId);
  }

  List<Chat> _visible() {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final c in _store.chats)
        if ((_filter != _Filter.unread || c.unread > 0) &&
            (_filter != _Filter.groups || c.isGroup) &&
            (q.isEmpty ||
                c.name.toLowerCase().contains(q) ||
                (c.otherUser?.username ?? '').contains(q) ||
                (c.lastMessage?.preview.toLowerCase().contains(q) ?? false)))
          c
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([OnlineService.instance, _store]),
      builder: (context, _) {
        if (!OnlineService.instance.signedIn) return const _SignInToChat();
        final list = _list(context);
        if (!_wide(context)) return list;
        final color = Theme.of(context).colorScheme;
        return Row(
          children: [
            SizedBox(width: 380, child: list),
            VerticalDivider(width: 1, color: color.outlineVariant.withAlpha(140)),
            Expanded(
              child: _selected == null
                  ? const Scaffold(
                      body: EmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Pick a chat',
                        body: 'Or start a new one. You can send notes and code blocks, and they arrive ready to run.',
                      ),
                    )
                  : ConversationPage(key: ValueKey(_selected), chatId: _selected!, embedded: true,
                      onClosed: () => setState(() => _selected = null)),
            ),
          ],
        );
      },
    );
  }

  Widget _list(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final chats = _visible();
    final me = OnlineService.instance.me;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: _searching ? 0 : null,
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _searching = false;
                  _search.clear();
                }))
            : null,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Search chats and messages', border: InputBorder.none, filled: false),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chats', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    _store.online ? '// connected' : '// connecting…',
                    style: monoStyle(context, size: 11, color: _store.online ? tokens.success : tokens.subtle),
                  ),
                ],
              ),
        actions: [
          if (!_searching)
            IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _searching = true)),
          if (me != null && !_searching)
            IconButton(
              tooltip: 'Your account',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountPage())),
              icon: Avatar.profile(me, size: 30),
            ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-chat',
        onPressed: _newChat,
        icon: const Icon(Icons.edit_square),
        label: const Text('New chat'),
      ),
      body: RefreshIndicator(
        onRefresh: _store.refresh,
        child: CustomScrollView(
          slivers: [
            if (_store.announcement != null) SliverToBoxAdapter(child: _AnnouncementBanner(_store.announcement!)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in _Filter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => 'All',
                          _Filter.unread => 'Unread',
                          _Filter.groups => 'Groups',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
            ),
            if (!_store.loaded && _store.error == null)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_store.error != null && _store.chats.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: "Can't load your chats",
                  body: _store.error,
                  action: FilledButton.icon(onPressed: _store.refresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
                ),
              )
            else if (chats.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: _store.chats.isEmpty ? Icons.forum_outlined : Icons.search_off_rounded,
                  title: _store.chats.isEmpty ? 'No chats yet' : 'Nothing here',
                  body: _store.chats.isEmpty ? 'Find people by name or @username, or scan their QR code.' : null,
                  action: _store.chats.isEmpty
                      ? FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.person_search_rounded), label: const Text('Find people'))
                      : null,
                ),
              )
            else
              SliverList.builder(
                itemCount: chats.length,
                itemBuilder: (context, i) => _ChatTile(
                  chat: chats[i],
                  selected: _wide(context) && chats[i].id == _selected,
                  onTap: () => _openChat(chats[i].id),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
      backgroundColor: color.surface,
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.selected, required this.onTap});
  final Chat chat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = ChatStore.instance;
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final last = chat.lastMessage;
    final mine = last?.senderId == store.myId;
    final typing = store.typingIn(chat.id);
    final online = chat.otherUser != null && store.isOnline(chat.otherUser!);
    final unread = chat.unread > 0;

    String preview;
    if (typing.isNotEmpty) {
      preview = chat.isGroup ? '${_firstName(store, chat, typing.first)} is typing…' : 'typing…';
    } else if (last == null) {
      preview = chat.isGroup ? 'Group created' : 'Say hello 👋';
    } else if (last.isSystem) {
      preview = systemLine(last, (id) => _firstName(store, chat, id), store.myId);
    } else {
      final who = mine ? 'You: ' : (chat.isGroup ? '${_firstName(store, chat, last.senderId)}: ' : '');
      preview = '$who${last.preview}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? color.primaryContainer.withAlpha(120) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall + 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBrand.radiusSmall + 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Avatar.chat(chat, size: 50, online: online),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                        ),
                        if (chat.muted) Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.notifications_off_outlined, size: 14, color: tokens.subtle),
                        ),
                        const SizedBox(width: 6),
                        Text(chatTime(chat.sortTime),
                            style: monoStyle(context, size: 11, color: unread ? color.primary : tokens.subtle)),
                      ]),
                      const SizedBox(height: 3),
                      Row(children: [
                        if (mine && last != null && !last.isSystem && typing.isEmpty) ...[
                          DeliveryTicks(last.pending ?? Delivery.sent, size: 14),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: typing.isNotEmpty ? color.primary : (unread ? color.onSurface : color.onSurfaceVariant),
                              fontStyle: last?.deleted == true ? FontStyle.italic : FontStyle.normal,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 22),
                            decoration: BoxDecoration(
                              color: chat.muted ? tokens.subtle : color.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              chat.unread > 99 ? '99+' : '${chat.unread}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: color.onPrimary, fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _firstName(ChatStore store, Chat chat, String? userId) {
  if (userId == null) return 'Someone';
  if (userId == store.myId) return 'You';
  final p = store.thread(chat.id).member(userId) ?? (chat.otherUser?.id == userId ? chat.otherUser : null);
  return p?.name.split(' ').first ?? 'Someone';
}

/// "Sara added Omar", "You renamed the group to Team".
String systemLine(ChatMessage m, String Function(String? id) nameOf, String? myId) {
  final p = m.payload ?? const {};
  final actor = nameOf(p['actor_id'] as String?);
  final target = nameOf(p['target_id'] as String?);
  return switch (p['event']) {
    'created' => '$actor created the group${p['name'] != null ? ' "${p['name']}"' : ''}',
    'added' => '$actor added $target',
    'removed' => '$actor removed $target',
    'left' => '$actor left',
    'renamed' => '$actor renamed the group to "${p['name'] ?? ''}"',
    'promoted' => '$actor made $target an admin',
    'demoted' => '$actor made $target a member',
    _ => 'Group updated',
  };
}

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner(this.a);
  final Announcement a;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final (icon, tint) = switch (a.kind) {
      'warning' => (Icons.warning_amber_rounded, tokens.pin),
      'update' => (Icons.rocket_launch_outlined, tokens.success),
      _ => (Icons.campaign_outlined, color.primary),
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: tint.withAlpha(28),
        borderRadius: BorderRadius.circular(AppBrand.radiusSmall + 2),
        border: Border.all(color: tint.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (a.body.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(a.body, style: TextStyle(color: color.onSurfaceVariant, height: 1.35)),
              ],
            ]),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: ChatStore.instance.dismissAnnouncement,
          ),
        ],
      ),
    );
  }
}

/// Shown on the chat screens when nobody is signed in.
class _SignInToChat extends StatelessWidget {
  const _SignInToChat();

  @override
  Widget build(BuildContext context) {
    final online = OnlineService.instance;
    final needsServer = online.stage == OnlineStage.needsServer;
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: EmptyState(
        icon: Icons.forum_outlined,
        title: 'Sign in to chat',
        body: 'Chats and notes sync need an account. Your notes on this device stay as they are.',
        action: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => needsServer ? ServerAddressPage(onBack: () => Navigator.pop(c)) : const AuthPage(),
            ),
          ),
          icon: const Icon(Icons.login_rounded),
          label: Text(needsServer ? 'Connect to a server' : 'Sign in'),
        ),
      ),
    );
  }
}
