import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/themes.dart';
import '../../features/notes/domain/entities/block.dart';
import '../../features/notes/domain/entities/note.dart';
import '../../features/notes/presentation/bloc/note_bloc.dart';
import '../../features/notes/presentation/bloc/note_state.dart';
import '../backend/backend.dart';
import '../chat/chat_store.dart';
import '../models.dart';
import 'chat_info_page.dart';
import 'chats_page.dart';
import 'common.dart';
import 'message_widgets.dart';

/// One conversation.
class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, required this.chatId, this.embedded = false, this.onClosed});
  final String chatId;

  /// Inside the two-pane layout (no back button).
  final bool embedded;
  final VoidCallback? onClosed;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  late final ChatThread _thread = ChatStore.instance.thread(widget.chatId);
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  bool _uploading = false;
  bool _showDown = false;
  int _newWhileUp = 0;
  int _seenCount = 0;
  String? _highlight;
  int _pinIndex = 0;

  /// The newest message I had read when opening: a "new messages" line goes above it.
  int? _unreadFrom;

  ChatStore get _store => ChatStore.instance;
  Chat? get _chat => _thread.details ?? _store.chatById(widget.chatId);
  String get _me => _store.myId ?? '';

  @override
  void initState() {
    super.initState();
    _store.visibleChatId = widget.chatId;
    final c = _store.chatById(widget.chatId);
    if (c != null && c.unread > 0) _unreadFrom = c.myReadSeq;
    _thread.open();
    _thread.addListener(_onThread);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (_store.visibleChatId == widget.chatId) _store.visibleChatId = null;
    _thread.removeListener(_onThread);
    _thread.close();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onThread() {
    final err = _thread.takeError();
    if (err != null && mounted) showSnack(context, err, error: true);
    final count = _thread.messages.length;
    if (count > _seenCount && _showDown) {
      final fresh = _thread.messages.take(count - _seenCount).where((m) => m.senderId != _me && !m.isSystem).length;
      _newWhileUp += fresh;
    }
    _seenCount = count;
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final down = _scroll.hasClients && _scroll.offset > 400;
    if (down != _showDown) {
      setState(() {
        _showDown = down;
        if (!down) _newWhileUp = 0;
      });
      if (!down) _thread.markRead();
    }
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) _thread.loadOlder();
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  /// Scrolls to a message (reply quotes, pinned bar) and flashes it.
  Future<void> _jumpTo(String id) async {
    var index = _thread.messages.indexWhere((m) => m.id == id);
    for (var i = 0; index < 0 && i < 10 && _thread.hasMore; i++) {
      await _thread.loadOlder();
      index = _thread.messages.indexWhere((m) => m.id == id);
    }
    if (index < 0) {
      if (mounted) showSnack(context, "That message isn't loaded anymore.");
      return;
    }
    setState(() => _highlight = id);
    // Rough position; the list sizes vary, so ensure-visible after a frame.
    if (_scroll.hasClients) {
      await _scroll.animateTo((index * 72.0).clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
    final ctx = _keys[id]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 250));
    }
    Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  final _keys = <String, GlobalKey>{};

  // ─── Sending ───────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final editing = _editing;
    if (editing != null) {
      _input.clear();
      setState(() => _editing = null);
      await attempt(context, () => _thread.edit(editing, text));
      return;
    }
    final reply = _replyTo;
    _input.clear();
    setState(() => _replyTo = null);
    await _thread.send(kind: MessageKind.text, body: text, replyTo: reply);
    _toBottom();
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.toLowerCase();
      final ext = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : (name.endsWith('.gif') ? 'gif' : 'jpg'));
      final type = ext == 'jpg' ? 'image/jpeg' : 'image/$ext';
      final url = await _store.backend.uploadImage(bytes, contentType: type, extension: ext);
      final caption = _input.text.trim();
      _input.clear();
      final reply = _replyTo;
      setState(() => _replyTo = null);
      await _thread.send(kind: MessageKind.image, body: caption, payload: {'url': url}, replyTo: reply);
      _toBottom();
    } catch (e) {
      if (mounted) showSnack(context, e is ApiError ? e.message : "The photo couldn't be sent: $e", error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _sendNoteOrBlock() async {
    final picked = await pickNoteToSend(context);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final reply = _replyTo;
      setState(() => _replyTo = null);
      if (picked.block != null) {
        final b = picked.block!;
        await _thread.send(
          kind: MessageKind.block,
          body: (b.text ?? '').length > 300 ? '${b.text!.substring(0, 300)}…' : (b.text ?? ''),
          payload: blockPayload(b),
          replyTo: reply,
        );
      } else {
        final ready = await prepareNoteForSending(picked.note);
        await _thread.send(kind: MessageKind.note, body: picked.note.title, payload: notePayload(ready), replyTo: reply);
      }
      _toBottom();
    } catch (e) {
      if (mounted) showSnack(context, e is ApiError ? e.message : "That couldn't be sent: $e", error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _attach() {
    final phone = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 12,
            children: [
              _AttachOption(icon: Icons.description_outlined, label: 'Note', color: AppBrand.violet, onTap: () {
                Navigator.pop(c);
                _sendNoteOrBlock();
              }),
              _AttachOption(icon: Icons.photo_library_outlined, label: 'Photo', color: AppBrand.blue, onTap: () {
                Navigator.pop(c);
                _sendPhoto(ImageSource.gallery);
              }),
              if (phone)
                _AttachOption(icon: Icons.photo_camera_outlined, label: 'Camera', color: AppBrand.magenta, onTap: () {
                  Navigator.pop(c);
                  _sendPhoto(ImageSource.camera);
                }),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Message actions ───────────────────────────────────

  void _actions(ChatMessage m) {
    HapticFeedback.mediumImpact();
    final chat = _chat;
    final mine = m.senderId == _me;
    final canPin = chat != null && (!chat.isGroup || chat.amAdmin) && !m.isSystem;
    final canDelete = mine || (chat?.amAdmin ?? false);
    final savable = m.kind == MessageKind.note || m.kind == MessageKind.block;
    const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in quick)
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    Navigator.pop(c);
                    attempt(context, () => _thread.react(m, e));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: m.reactions[_me] == e ? Theme.of(c).colorScheme.primary.withAlpha(40) : null,
                      shape: BoxShape.circle,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ]),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('Reply'),
            enabled: chat?.canSend ?? false,
            onTap: () {
              Navigator.pop(c);
              _reply(m);
            },
          ),
          if (m.body.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(c);
                Clipboard.setData(ClipboardData(text: m.kind == MessageKind.block ? (blockFromPayload(m.payload)?.text ?? m.body) : m.body));
                showSnack(context, 'Copied');
              },
            ),
          if (savable)
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Save to my notes'),
              onTap: () {
                Navigator.pop(c);
                saveToMyNotes(context, m);
                showSnack(context, 'Saved to your notes');
              },
            ),
          if (mine && (m.kind == MessageKind.text || m.kind == MessageKind.image))
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(c);
                setState(() {
                  _editing = m;
                  _replyTo = null;
                  _input.text = m.body;
                });
                _focus.requestFocus();
              },
            ),
          if (canPin)
            ListTile(
              leading: Icon(m.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
              title: Text(m.pinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(c);
                attempt(context, () => _thread.pin(m, !m.pinned));
              },
            ),
          if (mine)
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Info'),
              onTap: () {
                Navigator.pop(c);
                _info(m);
              },
            ),
          if (canDelete)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
              title: Text('Delete for everyone', style: TextStyle(color: Theme.of(c).colorScheme.error)),
              onTap: () async {
                Navigator.pop(c);
                if (await confirm(context, title: 'Delete this message?', body: 'It will say "This message was deleted" for everyone.', action: 'Delete')) {
                  if (mounted) attempt(context, () => _thread.delete(m));
                }
              },
            ),
        ]),
      ),
    );
  }

  void _reply(ChatMessage m) {
    setState(() {
      _replyTo = m;
      _editing = null;
    });
    _focus.requestFocus();
  }

  void _info(ChatMessage m) {
    final r = _thread.receiptsFor(m);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
          const SectionLabel('seen by', padding: EdgeInsets.fromLTRB(20, 0, 20, 6)),
          if (r.read.isEmpty) const ListTile(dense: true, title: Text('Nobody yet')),
          for (final p in r.read) ListTile(leading: Avatar.profile(p, size: 34), title: Text(p.name), trailing: const DeliveryTicks(Delivery.seen)),
          const SectionLabel('delivered to', padding: EdgeInsets.fromLTRB(20, 12, 20, 6)),
          if (r.delivered.isEmpty) const ListTile(dense: true, title: Text('Nobody else')),
          for (final p in r.delivered)
            ListTile(leading: Avatar.profile(p, size: 34), title: Text(p.name), trailing: const DeliveryTicks(Delivery.delivered)),
        ]),
      ),
    );
  }

  void _failed(ChatMessage m) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('Try again'),
            onTap: () {
              Navigator.pop(c);
              _thread.retry(m);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text("Don't send"),
            onTap: () {
              Navigator.pop(c);
              _thread.discard(m);
            },
          ),
        ]),
      ),
    );
  }

  // ─── Building ──────────────────────────────────────────

  String _nameOf(String? id) {
    if (id == null) return 'Someone';
    if (id == _me) return 'You';
    final p = _thread.member(id) ?? (_chat?.otherUser?.id == id ? _chat?.otherUser : null);
    return p?.name ?? 'Someone';
  }

  String _status(Chat chat) {
    final typing = _store.typingIn(chat.id);
    if (typing.isNotEmpty) {
      if (!chat.isGroup) return 'typing…';
      final names = typing.map((id) => _nameOf(id).split(' ').first).toList();
      return names.length == 1 ? '${names.first} is typing…' : '${names.length} people are typing…';
    }
    if (chat.isGroup) {
      final members = _thread.details?.members;
      final online = members?.where((m) => m.user.id != _me && _store.isOnline(m.user)).length ?? 0;
      final n = members?.length ?? chat.memberCount;
      return '$n members${online > 0 ? ' · $online online' : ''}';
    }
    final other = chat.otherUser;
    if (other == null || other.isDeleted) return '';
    if (chat.blocked == 'me') return 'blocked';
    return lastSeenLabel(_store.isOnline(other), _store.lastSeen(other));
  }

  void _openInfo() async {
    final chat = _chat;
    if (chat == null) return;
    final result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => ChatInfoPage(chatId: chat.id)));
    if (result == 'closed' && mounted) {
      if (widget.embedded) {
        widget.onClosed?.call();
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final chat = _chat;
        final color = Theme.of(context).colorScheme;
        final tokens = context.tokens;
        if (chat == null) {
          return Scaffold(
            appBar: AppBar(automaticallyImplyLeading: !widget.embedded),
            body: _thread.error != null
                ? EmptyState(icon: Icons.cloud_off_rounded, title: "Can't open this chat", body: _thread.error)
                : const Center(child: CircularProgressIndicator()),
          );
        }
        final status = _status(chat);
        final typing = _store.typingIn(chat.id).isNotEmpty;
        final online = chat.otherUser != null && _store.isOnline(chat.otherUser!);
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            titleSpacing: widget.embedded ? 16 : 0,
            title: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openInfo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Hero(tag: 'avatar-${chat.id}', child: Avatar.chat(chat, size: 38, online: online)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (status.isNotEmpty)
                        Text(status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: typing || online ? color.primary : tokens.subtle)),
                    ]),
                  ),
                ]),
              ),
            ),
            actions: [
              IconButton(tooltip: chat.isGroup ? 'Group info' : 'Contact info', icon: const Icon(Icons.info_outline_rounded), onPressed: _openInfo),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(children: [
            if (_thread.pinned.isNotEmpty) _pinnedBar(context),
            if (!_store.online) _offlineBar(context),
            Expanded(child: Stack(children: [
              _messages(context, chat),
              if (_showDown)
                Positioned(
                  right: 14,
                  bottom: 12,
                  child: Badge(
                    isLabelVisible: _newWhileUp > 0,
                    label: Text('$_newWhileUp'),
                    child: FloatingActionButton.small(
                      heroTag: 'down-${chat.id}',
                      tooltip: 'Go to the newest message',
                      onPressed: _toBottom,
                      child: const Icon(Icons.keyboard_double_arrow_down_rounded),
                    ),
                  ),
                ),
            ])),
            _composer(context, chat),
          ]),
        );
      },
    );
  }

  Widget _offlineBar(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      color: tokens.pin.withAlpha(30),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: tokens.pin)),
        const SizedBox(width: 10),
        const Expanded(child: Text('Connecting… Messages you write are sent when you\'re back online.', style: TextStyle(fontSize: 12.5))),
      ]),
    );
  }

  Widget _pinnedBar(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final pins = _thread.pinned;
    final i = _pinIndex % pins.length;
    final m = pins[i];
    return Material(
      color: color.surfaceContainerLow,
      child: InkWell(
        onTap: () {
          _jumpTo(m.id);
          setState(() => _pinIndex = i + 1);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color.outlineVariant.withAlpha(120)))),
          child: Row(children: [
            Container(width: 3, height: 32, decoration: BoxDecoration(color: color.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(pins.length > 1 ? 'Pinned message ${i + 1} of ${pins.length}' : 'Pinned message',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color.primary)),
                Text(m.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ]),
            ),
            Icon(Icons.push_pin_rounded, size: 18, color: color.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }

  Widget _messages(BuildContext context, Chat chat) {
    final msgs = _thread.messages;
    if (!_thread.loaded && msgs.isEmpty) {
      return _thread.error != null
          ? EmptyState(icon: Icons.cloud_off_rounded, title: "Can't load messages", body: _thread.error)
          : const Center(child: CircularProgressIndicator());
    }
    if (msgs.isEmpty) {
      return EmptyState(
        icon: chat.isGroup ? Icons.groups_rounded : Icons.waving_hand_outlined,
        title: chat.isGroup ? 'Welcome to ${chat.name}' : 'Say hello to ${chat.name}',
        body: 'Send a message, a photo, or a note or code block from your notes. Code arrives ready to run.',
      );
    }
    final typing = _store.typingIn(chat.id);
    final extra = (typing.isNotEmpty ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      itemCount: msgs.length + extra + (_thread.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (extra == 1 && index == 0) return _TypingBubble(name: chat.isGroup ? _nameOf(typing.first).split(' ').first : null);
        final i = index - extra;
        if (i >= msgs.length) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        final m = msgs[i];
        final older = i + 1 < msgs.length ? msgs[i + 1] : null;
        final newer = i > 0 ? msgs[i - 1] : null;
        final newDay = older == null || !_sameDay(older.createdAt, m.createdAt);
        final children = <Widget>[];
        if (newDay) children.add(CenterChip(dayLabel(m.createdAt)));
        if (_unreadFrom != null && m.seq > _unreadFrom! && (older == null || older.seq <= _unreadFrom!) && m.senderId != _me && !m.isPending) {
          children.add(const _NewMessagesLine());
        }
        if (m.isSystem) {
          children.add(CenterChip(systemLine(m, _nameOf, _me), icon: Icons.info_outline_rounded));
          return Column(children: children);
        }
        final mine = m.senderId == _me;
        final sameAsOlder = older != null && !older.isSystem && older.senderId == m.senderId && !newDay &&
            m.createdAt.difference(older.createdAt).inMinutes < 5;
        final sameAsNewer = newer != null && !newer.isSystem && newer.senderId == m.senderId &&
            _sameDay(newer.createdAt, m.createdAt) && newer.createdAt.difference(m.createdAt).inMinutes < 5;
        final showName = chat.isGroup && !mine && !sameAsOlder;
        final key = _keys.putIfAbsent(m.id, () => GlobalKey());
        final bubble = MessageBubble(
          key: key,
          message: m,
          mine: mine,
          myId: _me,
          delivery: mine ? _thread.delivery(m) : Delivery.sent,
          senderName: showName ? _nameOf(m.senderId) : null,
          senderSeed: m.senderId,
          showTail: !sameAsNewer,
          replyName: m.replyTo == null ? null : _nameOf(m.replyTo!.senderId),
          onTapReply: m.replyTo == null ? null : () => _jumpTo(m.replyTo!.id),
          onLongPress: m.deleted ? null : () => _actions(m),
          onReact: (e) => attempt(context, () => _thread.react(m, e)),
          onTapFailed: () => _failed(m),
          highlight: _highlight == m.id,
        );
        Widget row = Row(
          mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (chat.isGroup && !mine)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: sameAsNewer
                    ? const SizedBox(width: 30)
                    : (_thread.member(m.senderId) != null
                        ? Avatar.profile(_thread.member(m.senderId)!, size: 30)
                        : Avatar(seed: m.senderId ?? '', name: _nameOf(m.senderId), size: 30)),
              ),
            Flexible(child: bubble),
          ],
        );
        if (!m.deleted && !m.isPending && chat.canSend) row = _SwipeToReply(onReply: () => _reply(m), child: row);
        children.add(Padding(padding: EdgeInsets.only(top: sameAsOlder ? 0 : 6), child: row));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _composer(BuildContext context, Chat chat) {
    final color = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    if (!chat.canSend) {
      final (text, action) = switch (chat) {
        Chat(blocked: 'me') => ('You blocked ${chat.name}.', 'Unblock'),
        Chat(blocked: 'them') => ("You can't message ${chat.name}.", null),
        Chat(isGroup: true) => ('Only admins can send messages in this group.', null),
        _ => ('This account was deleted.', null),
      };
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(color: color.surfaceContainerLow, border: Border(top: BorderSide(color: color.outlineVariant.withAlpha(120)))),
          child: Row(children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: tokens.subtle),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color.onSurfaceVariant))),
            if (action != null && chat.otherUser != null)
              TextButton(
                onPressed: () => attempt(context, () async {
                  await _store.backend.unblock(chat.otherUser!.id);
                  await _store.refresh();
                }),
                child: Text(action),
              ),
          ]),
        ),
      );
    }
    final desktop = !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
    final hasText = _input.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(color: color.surface, border: Border(top: BorderSide(color: color.outlineVariant.withAlpha(90)))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_replyTo != null || _editing != null)
            Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                color: color.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: color.primary, width: 3)),
              ),
              child: Row(children: [
                Icon(_editing != null ? Icons.edit_outlined : Icons.reply_rounded, size: 18, color: color.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_editing != null ? 'Editing' : 'Replying to ${_nameOf(_replyTo!.senderId)}',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: color.primary)),
                    Text((_editing ?? _replyTo)!.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() {
                    if (_editing != null) _input.clear();
                    _replyTo = null;
                    _editing = null;
                  }),
                ),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Send a note, code, or photo',
              onPressed: _uploading || _editing != null ? null : _attach,
              icon: _uploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline_rounded),
            ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  if (desktop) const SingleActivator(LogicalKeyboardKey.enter): _sendText,
                  const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
                        _replyTo = null;
                        if (_editing != null) _input.clear();
                        _editing = null;
                      }),
                },
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) {
                    _thread.typing();
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: desktop ? 'Message  (Enter to send, Shift+Enter for a new line)' : 'Message',
                    isDense: true,
                    filled: true,
                    fillColor: color.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: color.primary.withAlpha(120))),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            AnimatedScale(
              duration: const Duration(milliseconds: 150),
              scale: hasText ? 1 : 0.85,
              child: IconButton.filled(
                tooltip: _editing != null ? 'Save' : 'Send',
                onPressed: hasText ? _sendText : null,
                icon: Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded, size: 20),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _NewMessagesLine extends StatelessWidget {
  const _NewMessagesLine();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Divider(color: color.primary.withAlpha(120))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('New messages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color.primary)),
        ),
        Expanded(child: Divider(color: color.primary.withAlpha(120))),
      ]),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({this.name});
  final String? name;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// Each dot brightens in turn.
  int _dotAlpha(int i) {
    final phase = (_anim.value * 3 - i) % 3;
    final t = phase < 1 ? 1 - (phase - 0.5).abs() * 2 : 0.0;
    return (80 + 170 * t).round();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2, left: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: color.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.name != null) ...[
            Text(widget.name!, style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
            const SizedBox(width: 8),
          ],
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Row(children: [
              for (var i = 0; i < 3; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color.onSurfaceVariant.withAlpha(_dotAlpha(i)),
                    shape: BoxShape.circle,
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Drag a message to the right to reply to it.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, 90.0).toDouble());
        if (_dx >= 64 && !_fired) {
          _fired = true;
          HapticFeedback.selectionClick();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply();
        setState(() {
          _dx = 0;
          _fired = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _fired = false;
      }),
      child: Stack(alignment: Alignment.centerLeft, children: [
        Opacity(
          opacity: (_dx / 64).clamp(0.0, 1.0).toDouble(),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.reply_rounded, color: color.primary),
          ),
        ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}

// ─── Picking a note to send ──────────────────────────────

/// Uploads pictures in [note] that are only on this device, so the other
/// person can see them.
Future<NoteEntity> prepareNoteForSending(NoteEntity note) async {
  final blocks = <BlockEntity>[];
  for (final b in note.blocks) {
    final path = b.imagePath;
    if (b is ImageBlockEntity && path != null && path.isNotEmpty && !path.startsWith('http') && !kIsWeb) {
      final file = File(path);
      if (await file.exists()) {
        final lower = path.toLowerCase();
        final ext = lower.endsWith('.png') ? 'png' : (lower.endsWith('.webp') ? 'webp' : 'jpg');
        final url = await ChatStore.instance.backend
            .uploadImage(await file.readAsBytes(), contentType: ext == 'jpg' ? 'image/jpeg' : 'image/$ext', extension: ext);
        blocks.add(b.copyWith(imagePath: url));
        continue;
      }
    }
    blocks.add(b);
  }
  return note.copyWith(blocks: blocks);
}

/// The person picks a note to send, or one block of it.
Future<({NoteEntity note, BlockEntity? block})?> pickNoteToSend(BuildContext context) {
  return showModalBottomSheet<({NoteEntity note, BlockEntity? block})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => const _NotePicker(),
  );
}

class _NotePicker extends StatefulWidget {
  const _NotePicker();

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  String _q = '';
  NoteEntity? _open;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final state = context.watch<NoteBloc>().state;
    final notes = state is NoteLoaded
        ? state.notes.where((n) => !n.isTrashed && (_q.isEmpty || n.title.toLowerCase().contains(_q))).toList()
        : <NoteEntity>[];
    notes.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) {
        final open = _open;
        if (open != null) {
          return ListView(controller: scroll, padding: const EdgeInsets.only(bottom: 24), children: [
            ListTile(
              leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _open = null)),
              title: Text(open.title.isEmpty ? 'Untitled' : open.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Send the whole note, or one block'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, (note: open, block: null)),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Send the whole note'),
              ),
            ),
            const SectionLabel('or one block'),
            for (final b in open.blocks.where((b) => b is! ImageBlockEntity && (b.text ?? '').trim().isNotEmpty))
              ListTile(
                leading: Icon(b is CodeBlockEntity ? Icons.code_rounded : Icons.notes_rounded),
                title: Text((b.text ?? '').trim().split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: b is CodeBlockEntity ? monoStyle(context, size: 13) : null),
                subtitle: Text(blockLabel(b), style: monoStyle(context, size: 11, color: tokens.subtle)),
                trailing: const Icon(Icons.send_rounded, size: 18),
                onTap: () => Navigator.pop(context, (note: open, block: b)),
              ),
          ]);
        }
        return ListView(controller: scroll, padding: const EdgeInsets.only(bottom: 24), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search your notes', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          if (notes.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No notes found'))),
          for (final n in notes.take(200))
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(n.title.isEmpty ? 'Untitled' : n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${n.blocks.length} blocks', style: monoStyle(context, size: 11, color: tokens.subtle)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => setState(() => _open = n),
            ),
        ]);
      },
    );
  }
}
