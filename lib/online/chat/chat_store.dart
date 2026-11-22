import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/v4.dart';

import '../../core/services/log_service.dart';
import '../backend/backend.dart';
import '../models.dart';

/// The chat list and every open conversation, kept up to date from live
/// events. Messages you send show at once and are kept until the server
/// has them, so nothing is lost offline or if the app closes.
class ChatStore extends ChangeNotifier {
  ChatStore._();
  static final instance = ChatStore._();

  Backend? _backend;
  String? _myId;
  StreamSubscription? _eventSub;
  StreamSubscription? _statusSub;
  Box? _outboxBox;

  List<Chat> _chats = const [];
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  final _threads = <String, ChatThread>{};
  final _typing = <String, Map<String, DateTime>>{};
  final _presence = <String, ({bool online, DateTime? lastSeen})>{};
  Announcement? _announcement;
  Timer? _refreshTimer;
  Timer? _typingTimer;

  /// The conversation on screen right now (read marks, notifications).
  String? visibleChatId;

  /// Called for new messages from others while their chat isn't on screen
  /// (the in-app banner).
  void Function(Chat chat, ChatMessage message)? onIncoming;

  List<Chat> get chats => _chats;
  bool get loaded => _loaded;
  bool get loading => _loading;
  String? get error => _error;
  String? get myId => _myId;
  bool get active => _backend != null;
  bool get online => _backend?.liveConnected ?? false;
  Announcement? get announcement => _announcement;
  Backend get backend => _backend!;

  int get totalUnread => _chats.where((c) => !c.muted).fold(0, (sum, c) => sum + c.unread);

  Chat? chatById(String id) {
    for (final c in _chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Who's typing in [chatId] right now (not me).
  List<String> typingIn(String chatId) {
    final now = DateTime.now();
    final m = _typing[chatId];
    if (m == null) return const [];
    return [
      for (final e in m.entries)
        if (now.difference(e.value) < const Duration(seconds: 6)) e.key
    ];
  }

  bool isOnline(Profile p) =>
      _presence[p.id]?.online ?? (_backend?.onlineUsers.contains(p.id) == true || p.online);

  DateTime? lastSeen(Profile p) => _presence[p.id]?.lastSeen ?? p.lastSeenAt;

  // ─── Start and stop ────────────────────────────────────

  Future<void> start(Backend backend, String myId) async {
    if (_backend == backend && _myId == myId) return;
    stop();
    _backend = backend;
    _myId = myId;
    _outboxBox = await Hive.openBox('chat_outbox_$myId');
    _eventSub = backend.events.listen(_onEvent);
    _statusSub = backend.liveStatus.listen((up) {
      notifyListeners();
      if (up) _flushOutbox();
    });
    _typingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_typing.isNotEmpty) {
        _typing.removeWhere((_, m) {
          m.removeWhere((_, t) => DateTime.now().difference(t) > const Duration(seconds: 6));
          return m.isEmpty;
        });
        notifyListeners();
      }
    });
    await refresh();
    _loadAnnouncement();
    unawaited(backend.markAllDelivered().catchError((_) {}));
    _flushOutbox();
  }

  void stop() {
    _eventSub?.cancel();
    _statusSub?.cancel();
    _refreshTimer?.cancel();
    _typingTimer?.cancel();
    for (final t in _threads.values) {
      t._disposed = true;
    }
    _threads.clear();
    _typing.clear();
    _presence.clear();
    _chats = const [];
    _loaded = false;
    _announcement = null;
    _backend = null;
    _myId = null;
    _outboxBox = null;
    visibleChatId = null;
    notifyListeners();
  }

  // ─── Chat list ─────────────────────────────────────────

  Future<void> refresh() async {
    final b = _backend;
    if (b == null || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final list = await b.chats();
      _chats = _withPending(list)..sort((a, z) => z.sortTime.compareTo(a.sortTime));
      _error = null;
      _loaded = true;
    } on ApiError catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong loading your chats.';
      LogService().log('Chats: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Several changes in a row: fetch the list once.
  void _refreshSoon() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 400), refresh);
  }

  List<Chat> _withPending(List<Chat> list) {
    // A chat where my unsent message is newest shows it as the last message.
    return [
      for (final c in list)
        () {
          final pending = _pendingFor(c.id);
          if (pending.isEmpty) return c;
          final newest = pending.first;
          return newest.createdAt.isAfter(c.sortTime) ? c.copyWith(lastMessage: newest) : c;
        }()
    ];
  }

  void _putChat(Chat chat) {
    final list = [..._chats.where((c) => c.id != chat.id), chat]..sort((a, z) => z.sortTime.compareTo(a.sortTime));
    _chats = list;
    notifyListeners();
  }

  /// Opens (or makes) the direct chat with [userId].
  Future<Chat> openDirect(String userId) async {
    final chat = await backend.startDirect(userId);
    _putChat(chat);
    return chat;
  }

  Future<Chat> createGroup({required String name, String description = '', String? imageUrl,
      required List<String> memberIds, bool adminOnly = false}) async {
    final chat = await backend.createGroup(
        name: name, description: description, imageUrl: imageUrl, memberIds: memberIds, adminOnly: adminOnly);
    _putChat(chat);
    return chat;
  }

  Future<void> setMuted(Chat chat, bool muted) async {
    _putChat(chat.copyWith(muted: muted));
    try {
      await backend.setMuted(chat.id, muted);
    } catch (e) {
      _putChat(chat);
      rethrow;
    }
  }

  Future<void> deleteChat(Chat chat) async {
    await backend.deleteChat(chat.id);
    _removeChat(chat.id);
  }

  Future<void> leaveGroup(Chat chat) async {
    await backend.removeMember(chat.id, _myId!);
    _removeChat(chat.id);
  }

  void _removeChat(String id) {
    _chats = _chats.where((c) => c.id != id).toList();
    _threads.remove(id)?._disposed = true;
    notifyListeners();
  }

  /// Call after changing a group or members on another page.
  void chatUpdated(Chat chat) {
    if (_chats.any((c) => c.id == chat.id)) _putChat(chat);
    _threads[chat.id]?._setDetails(chat);
  }

  // ─── Announcements ─────────────────────────────────────

  Future<void> _loadAnnouncement() async {
    try {
      final c = await backend.config();
      _setAnnouncement(c.announcement);
    } catch (_) {}
  }

  void _setAnnouncement(Announcement? a) {
    final dismissed = (_outboxBox?.get('dismissed_announcements') as List?)?.cast<String>() ?? const [];
    _announcement = a != null && a.active && !dismissed.contains(a.id) ? a : null;
    notifyListeners();
  }

  void dismissAnnouncement() {
    final a = _announcement;
    if (a == null) return;
    final dismissed = [...?(_outboxBox?.get('dismissed_announcements') as List?)?.cast<String>(), a.id];
    _outboxBox?.put('dismissed_announcements', dismissed.length > 50 ? dismissed.sublist(dismissed.length - 50) : dismissed);
    _announcement = null;
    notifyListeners();
  }

  // ─── Conversations ─────────────────────────────────────

  /// The conversation for [chatId] (kept while the app runs).
  ChatThread thread(String chatId) => _threads.putIfAbsent(chatId, () => ChatThread._(this, chatId));

  // ─── Outbox ────────────────────────────────────────────

  List<ChatMessage> _pendingFor(String chatId) {
    final box = _outboxBox;
    if (box == null) return const [];
    final out = <ChatMessage>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('msg:')) continue;
      try {
        final m = _fromOutbox(box.get(key) as String);
        if (m.chatId == chatId) out.add(m);
      } catch (_) {}
    }
    out.sort((a, z) => z.createdAt.compareTo(a.createdAt));
    return out;
  }

  ChatMessage _fromOutbox(String raw) {
    final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    return ChatMessage.fromJson(j).copyWith(pending: j['_failed'] == true ? Delivery.failed : Delivery.sending);
  }

  Future<void> _saveOutbox(ChatMessage m, {bool failed = false}) async =>
      _outboxBox?.put('msg:${m.clientId}', jsonEncode({...m.toJson(), '_failed': failed}));

  Future<void> _dropOutbox(String clientId) async => _outboxBox?.delete('msg:$clientId');

  bool _flushing = false;

  /// Sends everything waiting, oldest first.
  Future<void> _flushOutbox() async {
    final box = _outboxBox;
    final b = _backend;
    if (box == null || b == null || _flushing) return;
    _flushing = true;
    try {
      final waiting = <ChatMessage>[];
      for (final key in box.keys.toList()) {
        if (key is String && key.startsWith('msg:')) {
          try {
            final m = _fromOutbox(box.get(key) as String);
            if (m.pending == Delivery.sending) waiting.add(m);
          } catch (_) {
            await box.delete(key);
          }
        }
      }
      waiting.sort((a, z) => a.createdAt.compareTo(z.createdAt));
      for (final m in waiting) {
        final ok = await thread(m.chatId)._deliver(m);
        if (!ok) break; // still offline: try again when the connection is back
      }
    } finally {
      _flushing = false;
    }
  }

  // ─── Live events ───────────────────────────────────────

  void _onEvent(LiveEvent e) {
    switch (e) {
      case MessageEvent(:final message, :final isNew):
        _onMessage(message, isNew);
      case ChatChangedEvent(:final chatId):
        _refreshSoon();
        _threads[chatId]?._reloadDetails();
      case ChatRemovedEvent(:final chatId):
        _removeChat(chatId);
      case ReceiptEvent(:final chatId, :final userId, :final readSeq, :final deliveredSeq):
        _threads[chatId]?._receipt(userId, readSeq, deliveredSeq);
        if (userId == _myId) {
          final c = chatById(chatId);
          if (c != null && readSeq > c.myReadSeq) {
            _putChat(c.copyWith(unread: 0, myReadSeq: readSeq));
          }
        }
      case TypingEvent(:final chatId, :final userId):
        (_typing[chatId] ??= {})[userId] = DateTime.now();
        notifyListeners();
      case PresenceEvent(:final userId, :final online, :final lastSeenAt):
        _presence[userId] = (online: online, lastSeen: lastSeenAt);
        notifyListeners();
      case AnnouncementEvent(:final announcement):
        _setAnnouncement(announcement);
      case SyncEvent():
        break; // NotesSync listens to this itself
      case AccountDisabledEvent():
        break; // OnlineService signs out
      case ReconnectedEvent():
        refresh();
        for (final t in _threads.values) {
          t._catchUp();
        }
        _flushOutbox();
    }
  }

  void _onMessage(ChatMessage m, bool isNew) {
    _typing[m.chatId]?.remove(m.senderId);
    final thread = _threads[m.chatId];
    thread?._apply(m);
    final chat = chatById(m.chatId);
    if (chat == null) {
      _refreshSoon(); // a chat I don't have yet (new direct chat, added to a group)
      return;
    }
    final mine = m.senderId == _myId;
    final visible = visibleChatId == m.chatId;
    if (isNew) {
      final unread = mine || m.isSystem || visible ? chat.unread : chat.unread + 1;
      _putChat(chat.copyWith(lastMessage: m, unread: unread, updatedAt: m.createdAt));
      if (!mine && !m.isSystem) {
        if (visible) {
          thread?.markRead();
        } else {
          unawaited(backend.markDelivered(m.chatId, m.seq).catchError((_) {}));
          if (!chat.muted) onIncoming?.call(chat, m);
        }
      }
    } else if (chat.lastMessage?.id == m.id) {
      _putChat(chat.copyWith(lastMessage: m));
    }
  }

  void _notifyIfAlive() {
    if (_backend != null) notifyListeners();
  }
}

/// One conversation: its messages (newest first), members and read marks.
class ChatThread extends ChangeNotifier {
  ChatThread._(this.store, this.chatId);

  final ChatStore store;
  final String chatId;
  bool _disposed = false;

  List<ChatMessage> _messages = const [];
  bool _loaded = false;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String? _error;
  Chat? _details;
  List<ChatMessage> _pinned = const [];
  Timer? _readTimer;
  DateTime _lastTypingSent = DateTime(2000);

  List<ChatMessage> get messages => _messages;
  bool get loaded => _loaded;
  bool get loadingOlder => _loadingOlder;
  bool get hasMore => _hasMore;
  String? get error => _error;
  Chat? get details => _details;
  List<ChatMessage> get pinned => _pinned;
  Backend get _b => store.backend;
  String get _me => store.myId ?? '';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Profile? member(String? userId) {
    if (userId == null) return null;
    for (final m in _details?.members ?? const <ChatMember>[]) {
      if (m.user.id == userId) return m.user;
    }
    return null;
  }

  // ─── Loading ───────────────────────────────────────────

  Future<void> open() async {
    _b.watchChat(chatId);
    if (!_loaded) {
      await Future.wait([_loadLatest(), _reloadDetails(), _loadPinned()]);
    } else {
      await _catchUp();
    }
    markRead();
  }

  void close() {
    if (store.active) store.backend.unwatchChat(chatId);
  }

  Future<void> _loadLatest() async {
    try {
      final latest = await _b.messages(chatId, limit: 50);
      _messages = _merge(latest, store._pendingFor(chatId));
      _hasMore = latest.length >= 50;
      _loaded = true;
      _error = null;
    } on ApiError catch (e) {
      _error = e.message;
      if (!_loaded) _messages = store._pendingFor(chatId);
    }
    _changed();
  }

  Future<void> loadOlder() async {
    if (_loadingOlder || !_hasMore || !_loaded) return;
    final oldest = _messages.lastWhere((m) => m.seq > 0, orElse: () => _messages.isEmpty ? _empty : _messages.last);
    if (oldest.seq == 0) return;
    _loadingOlder = true;
    _changed();
    try {
      final older = await _b.messages(chatId, beforeSeq: oldest.seq, limit: 50);
      _hasMore = older.length >= 50;
      _messages = _merge([..._messages, ...older], const []);
    } catch (_) {}
    _loadingOlder = false;
    _changed();
  }

  static final _empty = ChatMessage(id: '', seq: 0, chatId: '', kind: MessageKind.text, createdAt: DateTime(2000));

  /// After being offline: get what was missed.
  Future<void> _catchUp() async {
    final newest = _messages.firstWhere((m) => m.seq > 0, orElse: () => _empty);
    if (newest.seq == 0) return _loadLatest();
    try {
      var after = newest.seq;
      for (var i = 0; i < 10; i++) {
        final more = await _b.messages(chatId, afterSeq: after, limit: 200);
        if (more.isEmpty) break;
        _messages = _merge([...more, ..._messages], const []);
        after = more.first.seq;
        if (more.length < 200) break;
      }
      // Edits, reactions and deletions while away: refresh the recent ones.
      final recent = await _b.messages(chatId, limit: 50);
      _messages = _merge([...recent, ..._messages], const []);
      _changed();
      await _reloadDetails();
    } catch (_) {}
  }

  Future<void> _reloadDetails() async {
    try {
      _setDetails(await _b.chat(chatId));
    } catch (_) {}
  }

  void _setDetails(Chat chat) {
    _details = chat;
    _changed();
  }

  Future<void> _loadPinned() async {
    try {
      _pinned = await _b.pinned(chatId);
      _changed();
    } catch (_) {}
  }

  /// Newest first, one copy of each message (a sent message replaces its
  /// pending copy).
  List<ChatMessage> _merge(List<ChatMessage> server, List<ChatMessage> pending) {
    final byId = <String, ChatMessage>{};
    final clientIds = <String>{};
    for (final m in server) {
      final old = byId[m.id];
      if (old == null || m.seq >= old.seq) byId[m.id] = m;
      if (m.clientId != null) clientIds.add(m.clientId!);
    }
    final out = byId.values.toList();
    for (final p in [...pending, ..._messages.where((m) => m.isPending)]) {
      if (!clientIds.contains(p.clientId) && !out.any((m) => m.id == p.id)) out.add(p);
    }
    out.sort((a, z) {
      if (a.isPending != z.isPending) return a.isPending ? -1 : 1; // unsent at the bottom of the chat
      if (a.isPending) return z.createdAt.compareTo(a.createdAt);
      return z.seq.compareTo(a.seq);
    });
    return out;
  }

  // ─── Live ──────────────────────────────────────────────

  void _apply(ChatMessage m) {
    if (!_loaded) return;
    _messages = _merge([m, ..._messages.where((x) => !x.isPending || x.clientId != m.clientId)], const []);
    final wasPinned = _pinned.any((p) => p.id == m.id);
    if (m.pinned != wasPinned || (wasPinned && m.deleted)) {
      _pinned = m.pinned && !m.deleted
          ? [m, ..._pinned.where((p) => p.id != m.id)]
          : _pinned.where((p) => p.id != m.id).toList();
    } else if (wasPinned) {
      _pinned = [for (final p in _pinned) p.id == m.id ? m : p];
    }
    _changed();
  }

  void _receipt(String userId, int readSeq, int deliveredSeq) {
    final d = _details;
    if (d?.members == null) return;
    _details = d!.copyWith(members: [
      for (final m in d.members!)
        m.user.id == userId
            ? m.withReceipt(read: readSeq > m.readSeq ? readSeq : null, delivered: deliveredSeq > m.deliveredSeq ? deliveredSeq : null)
            : m
    ]);
    _changed();
  }

  /// Sent, delivered or seen, from the other members' read marks.
  Delivery delivery(ChatMessage m) {
    if (m.pending != null) return m.pending!;
    final others = (_details?.members ?? const <ChatMember>[]).where((x) => x.user.id != _me && !x.user.isDeleted).toList();
    if (others.isEmpty) return Delivery.sent;
    if (others.every((x) => x.readSeq >= m.seq)) return Delivery.seen;
    if (others.every((x) => x.deliveredSeq >= m.seq)) return Delivery.delivered;
    return Delivery.sent;
  }

  /// For the message info sheet: who has read it, who has it.
  ({List<Profile> read, List<Profile> delivered}) receiptsFor(ChatMessage m) {
    final others = (_details?.members ?? const <ChatMember>[]).where((x) => x.user.id != _me);
    return (
      read: [for (final x in others) if (x.readSeq >= m.seq) x.user],
      delivered: [for (final x in others) if (x.readSeq < m.seq && x.deliveredSeq >= m.seq) x.user],
    );
  }

  void markRead() {
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(milliseconds: 300), () async {
      final newest = _messages.firstWhere((m) => m.seq > 0, orElse: () => _empty);
      final chat = store.chatById(chatId);
      if (newest.seq == 0 || store.visibleChatId != chatId) return;
      if (chat != null && chat.myReadSeq >= newest.seq && chat.unread == 0) return;
      if (chat != null) store._putChat(chat.copyWith(unread: 0, myReadSeq: newest.seq));
      try {
        await _b.markRead(chatId, newest.seq);
      } catch (_) {}
    });
  }

  void typing() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent) < const Duration(seconds: 3)) return;
    _lastTypingSent = now;
    _b.sendTyping(chatId);
  }

  // ─── Sending ───────────────────────────────────────────

  Future<void> send({required MessageKind kind, String body = '', Map<String, dynamic>? payload, ChatMessage? replyTo}) async {
    final clientId = const UuidV4().generate();
    final m = ChatMessage(
      id: 'local-$clientId',
      seq: 0,
      chatId: chatId,
      senderId: _me,
      clientId: clientId,
      kind: kind,
      body: body,
      payload: payload,
      replyTo: replyTo == null
          ? null
          : ReplyPreview(id: replyTo.id, senderId: replyTo.senderId, kind: replyTo.kind, body: replyTo.preview),
      createdAt: DateTime.now(),
      pending: Delivery.sending,
    );
    await store._saveOutbox(m);
    _messages = [m, ..._messages];
    _changed();
    final chat = store.chatById(chatId);
    if (chat != null) store._putChat(chat.copyWith(lastMessage: m, updatedAt: m.createdAt));
    await _deliver(m);
  }

  /// Sends a waiting message. False if offline (it stays waiting).
  Future<bool> _deliver(ChatMessage m) async {
    try {
      final sent = await _b.send(chatId,
          clientId: m.clientId!, kind: m.kind, body: m.body, payload: m.payload, replyToId: m.replyTo?.id);
      await store._dropOutbox(m.clientId!);
      _messages = _merge([sent, ..._messages.where((x) => x.clientId != m.clientId)], const []);
      _changed();
      final chat = store.chatById(chatId);
      if (chat != null && (chat.lastMessage == null || chat.lastMessage!.clientId == m.clientId || sent.seq >= chat.lastMessage!.seq)) {
        store._putChat(chat.copyWith(lastMessage: sent));
      }
      return true;
    } on ApiError catch (e) {
      if (e.offline) return false;
      // The server said no (blocked, not allowed): it won't work on retry.
      await store._saveOutbox(m, failed: true);
      _messages = [for (final x in _messages) x.clientId == m.clientId ? x.copyWith(pending: Delivery.failed) : x];
      _error = e.message;
      _changed();
      store._notifyIfAlive();
      return true;
    }
  }

  Future<void> retry(ChatMessage m) async {
    final again = m.copyWith(pending: Delivery.sending);
    await store._saveOutbox(again);
    _messages = [for (final x in _messages) x.clientId == m.clientId ? again : x];
    _changed();
    await _deliver(again);
  }

  Future<void> discard(ChatMessage m) async {
    await store._dropOutbox(m.clientId ?? '');
    _messages = _messages.where((x) => x.clientId != m.clientId).toList();
    _changed();
  }

  String? takeError() {
    final e = _error;
    _error = null;
    return e;
  }

  // ─── Changing messages ─────────────────────────────────

  Future<void> _replace(Future<ChatMessage> Function() run) async {
    final m = await run();
    _apply(m);
    final chat = store.chatById(chatId);
    if (chat?.lastMessage?.id == m.id) store._putChat(chat!.copyWith(lastMessage: m));
  }

  Future<void> edit(ChatMessage m, String body) => _replace(() => _b.edit(m.id, body));
  Future<void> delete(ChatMessage m) => _replace(() => _b.delete(m.id));
  Future<void> pin(ChatMessage m, bool pinned) => _replace(() => _b.pin(m.id, pinned));

  Future<void> react(ChatMessage m, String emoji) {
    // The same emoji again takes the reaction back.
    if (m.reactions[_me] == emoji) return _replace(() => _b.unreact(m.id));
    return _replace(() => _b.react(m.id, emoji));
  }
}
