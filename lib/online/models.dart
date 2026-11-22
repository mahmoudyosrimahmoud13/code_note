import 'package:flutter/widgets.dart';

// The data shapes in docs/online/CONTRACT.md. Both backends give back the
// same JSON, so one set of classes reads both.

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
bool _bool(Object? v) => v == true;
String _str(Object? v) => v == null ? '' : '$v';
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.username,
    this.avatarUrl,
    this.about = '',
    this.email,
    this.emailVerified = true,
    this.isAdmin = false,
    this.isDisabled = false,
    this.isDeleted = false,
    this.createdAt,
    this.lastSeenAt,
    this.online = false,
  });

  final String id;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String about;
  final String? email;
  final bool emailVerified;
  final bool isAdmin;
  final bool isDisabled;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final bool online;

  String get handle => username == null ? '' : '@$username';

  /// Initials for an avatar without a picture.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: _str(j['id']),
        name: _str(j['name']).isEmpty ? 'Someone' : _str(j['name']),
        username: j['username'] as String?,
        avatarUrl: (j['avatar_url'] as String?)?.isEmpty == true ? null : j['avatar_url'] as String?,
        about: _str(j['about']),
        email: j['email'] as String?,
        emailVerified: j['email_verified'] != false,
        isAdmin: _bool(j['is_admin']),
        isDisabled: _bool(j['is_disabled']),
        isDeleted: _bool(j['is_deleted']),
        createdAt: _date(j['created_at']),
        lastSeenAt: _date(j['last_seen_at']),
        online: _bool(j['online']),
      );

  Profile copyWith({bool? online, DateTime? lastSeenAt, String? name, String? username, String? avatarUrl,
          String? about, bool? emailVerified}) =>
      Profile(
        id: id,
        name: name ?? this.name,
        username: username ?? this.username,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        about: about ?? this.about,
        email: email,
        emailVerified: emailVerified ?? this.emailVerified,
        isAdmin: isAdmin,
        isDisabled: isDisabled,
        isDeleted: isDeleted,
        createdAt: createdAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        online: online ?? this.online,
      );
}

/// A user profile page: the profile plus how it relates to me.
class UserPage {
  const UserPage(this.profile, {this.blockedByMe = false, this.commonGroups = const []});
  final Profile profile;
  final bool blockedByMe;
  final List<({String id, String name, String? imageUrl})> commonGroups;

  factory UserPage.fromJson(Map<String, dynamic> j) => UserPage(
        Profile.fromJson(j),
        blockedByMe: _bool(j['blocked_by_me']),
        commonGroups: [
          for (final g in (j['common_groups'] as List? ?? const []))
            (id: _str(_map(g)['id']), name: _str(_map(g)['name']), imageUrl: _map(g)['image_url'] as String?),
        ],
      );
}

enum MessageKind { text, note, block, image, system }

MessageKind _kind(Object? v) =>
    MessageKind.values.firstWhere((k) => k.name == v, orElse: () => MessageKind.text);

class ReplyPreview {
  const ReplyPreview({required this.id, this.senderId, required this.kind, required this.body});
  final String id;
  final String? senderId;
  final MessageKind kind;
  final String body;

  factory ReplyPreview.fromJson(Map<String, dynamic> j) =>
      ReplyPreview(id: _str(j['id']), senderId: j['sender_id'] as String?, kind: _kind(j['kind']), body: _str(j['body']));
}

/// Where a message is on its way: only for my own messages.
enum Delivery { sending, failed, sent, delivered, seen }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.seq,
    required this.chatId,
    this.senderId,
    this.clientId,
    required this.kind,
    this.body = '',
    this.payload,
    this.replyTo,
    this.reactions = const {},
    this.pinned = false,
    this.edited = false,
    this.deleted = false,
    required this.createdAt,
    this.pending,
  });

  final String id;

  /// 0 while it's still being sent.
  final int seq;
  final String chatId;
  final String? senderId;
  final String? clientId;
  final MessageKind kind;
  final String body;
  final Map<String, dynamic>? payload;
  final ReplyPreview? replyTo;
  final Map<String, String> reactions;
  final bool pinned;
  final bool edited;
  final bool deleted;
  final DateTime createdAt;

  /// Set for messages that haven't reached the server: sending or failed.
  final Delivery? pending;

  bool get isPending => pending != null;
  bool get isSystem => kind == MessageKind.system;
  String? get imageUrl => payload?['url'] as String?;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _str(j['id']),
        seq: _int(j['seq']),
        chatId: _str(j['chat_id']),
        senderId: j['sender_id'] as String?,
        clientId: j['client_id'] as String?,
        kind: _kind(j['kind']),
        body: _str(j['body']),
        payload: j['payload'] is Map ? Map<String, dynamic>.from(j['payload'] as Map) : null,
        replyTo: j['reply_to'] is Map ? ReplyPreview.fromJson(_map(j['reply_to'])) : null,
        reactions: {for (final e in _map(j['reactions']).entries) e.key: '${e.value}'},
        pinned: _bool(j['pinned']),
        edited: _bool(j['edited']),
        deleted: _bool(j['deleted']),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'seq': seq,
        'chat_id': chatId,
        'sender_id': senderId,
        'client_id': clientId,
        'kind': kind.name,
        'body': body,
        'payload': payload,
        'reply_to': replyTo == null
            ? null
            : {'id': replyTo!.id, 'sender_id': replyTo!.senderId, 'kind': replyTo!.kind.name, 'body': replyTo!.body},
        'reactions': reactions,
        'pinned': pinned,
        'edited': edited,
        'deleted': deleted,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  ChatMessage copyWith({Delivery? pending, bool clearPending = false, String? body, bool? edited}) => ChatMessage(
        id: id,
        seq: seq,
        chatId: chatId,
        senderId: senderId,
        clientId: clientId,
        kind: kind,
        body: body ?? this.body,
        payload: payload,
        replyTo: replyTo,
        reactions: reactions,
        pinned: pinned,
        edited: edited ?? this.edited,
        deleted: deleted,
        createdAt: createdAt,
        pending: clearPending ? null : (pending ?? this.pending),
      );

  /// A short line for chat lists and notifications.
  String get preview => switch (kind) {
        _ when deleted => 'This message was deleted',
        MessageKind.image => body.isEmpty ? '📷 Photo' : '📷 $body',
        MessageKind.note => '📝 ${(payload?['title'] as String?)?.trim().isNotEmpty == true ? payload!['title'] : 'Untitled note'}',
        MessageKind.block => '‹/› ${body.isNotEmpty ? body.split('\n').first : 'Code block'}',
        MessageKind.system => 'Group update',
        MessageKind.text => body,
      };
}

class ChatMember {
  const ChatMember({required this.user, required this.role, this.joinedAt, this.readSeq = 0, this.deliveredSeq = 0});
  final Profile user;
  final String role;
  final DateTime? joinedAt;
  final int readSeq;
  final int deliveredSeq;
  bool get isAdmin => role == 'admin';

  factory ChatMember.fromJson(Map<String, dynamic> j) => ChatMember(
        user: Profile.fromJson(_map(j['user'])),
        role: _str(j['role']),
        joinedAt: _date(j['joined_at']),
        readSeq: _int(j['read_seq']),
        deliveredSeq: _int(j['delivered_seq']),
      );

  ChatMember withReceipt({int? read, int? delivered}) => ChatMember(
        user: user,
        role: role,
        joinedAt: joinedAt,
        readSeq: read ?? readSeq,
        deliveredSeq: delivered ?? deliveredSeq,
      );

  ChatMember withUser(Profile p) =>
      ChatMember(user: p, role: role, joinedAt: joinedAt, readSeq: readSeq, deliveredSeq: deliveredSeq);
}

class Chat {
  const Chat({
    required this.id,
    required this.isGroup,
    required this.name,
    this.description = '',
    this.imageUrl,
    this.adminOnly = false,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.lastMessage,
    this.unread = 0,
    this.muted = false,
    this.myRole = 'member',
    this.memberCount = 0,
    this.otherUser,
    this.blocked,
    this.myReadSeq = 0,
    this.members,
  });

  final String id;
  final bool isGroup;
  final String name;
  final String description;
  final String? imageUrl;
  final bool adminOnly;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final ChatMessage? lastMessage;
  final int unread;
  final bool muted;
  final String myRole;
  final int memberCount;
  final Profile? otherUser;

  /// Direct chats: 'me' (I blocked them), 'them', or null.
  final String? blocked;
  final int myReadSeq;

  /// Only in chat details.
  final List<ChatMember>? members;

  bool get amAdmin => isGroup && myRole == 'admin';
  bool get canSend => !(isGroup && adminOnly && !amAdmin) && blocked == null && !(otherUser?.isDeleted ?? false);
  DateTime get sortTime => lastMessage?.createdAt ?? updatedAt ?? createdAt ?? DateTime(2000);

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: _str(j['id']),
        isGroup: _bool(j['is_group']),
        name: _str(j['name']).isEmpty ? 'Chat' : _str(j['name']),
        description: _str(j['description']),
        imageUrl: (j['image_url'] as String?)?.isEmpty == true ? null : j['image_url'] as String?,
        adminOnly: _bool(j['admin_only']),
        createdBy: j['created_by'] as String?,
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        lastMessage: j['last_message'] is Map ? ChatMessage.fromJson(_map(j['last_message'])) : null,
        unread: _int(j['unread']),
        muted: _bool(j['muted']),
        myRole: _str(j['my_role']).isEmpty ? 'member' : _str(j['my_role']),
        memberCount: _int(j['member_count']),
        otherUser: j['other_user'] is Map ? Profile.fromJson(_map(j['other_user'])) : null,
        blocked: j['blocked'] as String?,
        myReadSeq: _int(j['my_read_seq']),
        members: j['members'] is List
            ? [for (final m in j['members'] as List) ChatMember.fromJson(_map(m))]
            : null,
      );

  Chat copyWith({
    ChatMessage? lastMessage,
    int? unread,
    bool? muted,
    List<ChatMember>? members,
    Profile? otherUser,
    int? myReadSeq,
    DateTime? updatedAt,
  }) =>
      Chat(
        id: id,
        isGroup: isGroup,
        name: name,
        description: description,
        imageUrl: imageUrl,
        adminOnly: adminOnly,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastMessage: lastMessage ?? this.lastMessage,
        unread: unread ?? this.unread,
        muted: muted ?? this.muted,
        myRole: myRole,
        memberCount: memberCount,
        otherUser: otherUser ?? this.otherUser,
        blocked: blocked,
        myReadSeq: myReadSeq ?? this.myReadSeq,
        members: members ?? this.members,
      );
}

class Announcement {
  const Announcement({required this.id, required this.title, this.body = '', this.kind = 'info', this.active = true, this.createdAt});
  final String id;
  final String title;
  final String body;
  final String kind;
  final bool active;
  final DateTime? createdAt;

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        kind: _str(j['kind']).isEmpty ? 'info' : _str(j['kind']),
        active: j['active'] != false,
        createdAt: _date(j['created_at']),
      );
}

class ServerConfig {
  const ServerConfig({this.name = '', this.signupEnabled = true, this.maintenanceMessage = '', this.announcement,
      this.emailVerification = false, this.googleEnabled = false});
  final String name;
  final bool signupEnabled;
  final String maintenanceMessage;
  final Announcement? announcement;
  final bool emailVerification;
  final bool googleEnabled;

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        name: _str(j['name']),
        signupEnabled: j['signup_enabled'] != false,
        maintenanceMessage: _str(j['maintenance_message']),
        announcement: j['announcement'] is Map ? Announcement.fromJson(_map(j['announcement'])) : null,
        emailVerification: _bool(j['email_verification']),
        googleEnabled: (j['google_client_ids'] as List?)?.isNotEmpty ?? false,
      );
}

class AppSettingsInfo {
  const AppSettingsInfo({required this.signupEnabled, required this.userLimit, required this.maintenanceMessage});
  final bool signupEnabled;
  final int userLimit;
  final String maintenanceMessage;

  factory AppSettingsInfo.fromJson(Map<String, dynamic> j) => AppSettingsInfo(
        signupEnabled: j['signup_enabled'] != false,
        userLimit: _int(j['user_limit']),
        maintenanceMessage: _str(j['maintenance_message']),
      );
}

class AdminStats {
  const AdminStats(this.values);
  final Map<String, int> values;
  int operator [](String key) => values[key] ?? 0;
  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats({for (final e in j.entries) e.key: _int(e.value)});
}

class SyncItem {
  const SyncItem({required this.kind, required this.id, this.data, this.deleted = false, this.rev = 0});
  final String kind;
  final String id;
  final Map<String, dynamic>? data;
  final bool deleted;
  final int rev;

  factory SyncItem.fromJson(Map<String, dynamic> j) => SyncItem(
        kind: _str(j['kind']),
        id: _str(j['id']),
        data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : null,
        deleted: _bool(j['deleted']),
        rev: _int(j['rev']),
      );
}

class SyncPull {
  const SyncPull({required this.rev, required this.latest, required this.items});
  final int rev;
  final int latest;
  final List<SyncItem> items;
  factory SyncPull.fromJson(Map<String, dynamic> j) => SyncPull(
        rev: _int(j['rev']),
        latest: _int(j['latest']),
        items: [for (final i in (j['items'] as List? ?? const [])) SyncItem.fromJson(_map(i))],
      );
}

class SyncPushResult {
  const SyncPushResult({required this.rev, required this.applied, required this.conflicts});
  final int rev;
  final List<String> applied;
  final List<SyncItem> conflicts;
  factory SyncPushResult.fromJson(Map<String, dynamic> j) => SyncPushResult(
        rev: _int(j['rev']),
        applied: [for (final a in (j['applied'] as List? ?? const [])) '$a'],
        conflicts: [for (final c in (j['conflicts'] as List? ?? const [])) SyncItem.fromJson(_map(c))],
      );
}

/// Something that happened on the server, live. Both backends turn their
/// own updates into these.
sealed class LiveEvent {
  const LiveEvent();
}

class MessageEvent extends LiveEvent {
  const MessageEvent(this.message, {required this.isNew});
  final ChatMessage message;
  final bool isNew;
}

class ChatChangedEvent extends LiveEvent {
  const ChatChangedEvent(this.chatId);
  final String chatId;
}

class ChatRemovedEvent extends LiveEvent {
  const ChatRemovedEvent(this.chatId);
  final String chatId;
}

class ReceiptEvent extends LiveEvent {
  const ReceiptEvent({required this.chatId, required this.userId, required this.readSeq, required this.deliveredSeq});
  final String chatId;
  final String userId;
  final int readSeq;
  final int deliveredSeq;
}

class TypingEvent extends LiveEvent {
  const TypingEvent(this.chatId, this.userId);
  final String chatId;
  final String userId;
}

class PresenceEvent extends LiveEvent {
  const PresenceEvent(this.userId, this.online, this.lastSeenAt);
  final String userId;
  final bool online;
  final DateTime? lastSeenAt;
}

class AnnouncementEvent extends LiveEvent {
  const AnnouncementEvent(this.announcement);
  final Announcement announcement;
}

class SyncEvent extends LiveEvent {
  const SyncEvent(this.rev);
  final int rev;
}

class AccountDisabledEvent extends LiveEvent {
  const AccountDisabledEvent();
}

/// The live connection came back after being down: fetch what was missed.
class ReconnectedEvent extends LiveEvent {
  const ReconnectedEvent();
}

/// Parses a WebSocket event (the FastAPI server's format).
LiveEvent? liveEventFromJson(Map<String, dynamic> j) {
  switch (j['type']) {
    case 'message.new':
      return MessageEvent(ChatMessage.fromJson(_map(j['message'])), isNew: true);
    case 'message.updated':
      return MessageEvent(ChatMessage.fromJson(_map(j['message'])), isNew: false);
    case 'chat.updated':
      return ChatChangedEvent(_str(j['chat_id']));
    case 'chat.removed':
      return ChatRemovedEvent(_str(j['chat_id']));
    case 'receipt':
      return ReceiptEvent(
        chatId: _str(j['chat_id']),
        userId: _str(j['user_id']),
        readSeq: _int(j['read_seq']),
        deliveredSeq: _int(j['delivered_seq']),
      );
    case 'typing':
      return TypingEvent(_str(j['chat_id']), _str(j['user_id']));
    case 'presence':
      return PresenceEvent(_str(j['user_id']), _bool(j['online']), _date(j['last_seen_at']));
    case 'announcement':
      return AnnouncementEvent(Announcement.fromJson(_map(j['announcement'])));
    case 'sync':
      return SyncEvent(_int(j['rev']));
    case 'account.disabled':
      return const AccountDisabledEvent();
  }
  return null;
}
