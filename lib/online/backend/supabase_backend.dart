import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/v4.dart';

import '../models.dart';
import 'backend.dart';

/// Talks to Supabase: Auth for accounts, SQL functions (supabase/migrations)
/// for everything else, Realtime for live updates, Storage for pictures.
class SupabaseBackend extends Backend {
  SupabaseBackend(this._db) {
    _authSub = _db.auth.onAuthStateChange.listen((state) {
      if (state.event == sb.AuthChangeEvent.signedOut && _signedIn) {
        _signedIn = false;
        onSignedOut?.call('You were signed out.');
      }
    });
  }

  final sb.SupabaseClient _db;
  late final StreamSubscription _authSub;
  bool _signedIn = false;

  String? get _uid => _db.auth.currentUser?.id;

  /// Runs a SQL function and turns its errors into plain words.
  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _db.rpc(fn, params: params);
    } on sb.PostgrestException catch (e) {
      throw ApiError(_clean(e.message), status: e.code == '42501' ? 403 : 400);
    } on sb.AuthException catch (e) {
      throw ApiError(_authMessage(e.message), status: 401);
    } catch (e) {
      throw const ApiError("You're offline, or Supabase can't be reached.", offline: true);
    }
  }

  static String _clean(String message) {
    // Postgres sometimes adds "ERROR: " or the function name in front.
    return message.replaceFirst(RegExp(r'^ERROR:\s*'), '');
  }

  Future<Map<String, dynamic>> _obj(String fn, [Map<String, dynamic>? params]) async =>
      Map<String, dynamic>.from((await _rpc(fn, params)) as Map);

  Future<List<Map<String, dynamic>>> _list(String fn, [Map<String, dynamic>? params]) async =>
      [for (final x in ((await _rpc(fn, params)) as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

  Future<T> _auth<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on sb.AuthException catch (e) {
      throw ApiError(_authMessage(e.message), status: 401);
    } catch (e) {
      if (e is ApiError) rethrow;
      throw const ApiError("You're offline, or Supabase can't be reached.", offline: true);
    }
  }

  static String _authMessage(String raw) {
    // Some Supabase errors arrive as the raw reply, like
    // {"code":"unexpected_failure","message":"Error sending confirmation email"}.
    // Take the readable part out of it.
    var m = raw.trim();
    if (m.startsWith('{')) {
      try {
        final j = jsonDecode(m);
        if (j is Map) {
          final inner = j['message'] ?? j['msg'] ?? j['error_description'] ?? j['error'];
          if (inner is String && inner.trim().isNotEmpty) m = inner.trim();
        }
      } catch (_) {}
    }
    final lower = m.toLowerCase();
    if (lower.contains('error sending') && lower.contains('email')) {
      return "We couldn't send the email right now. Try again in a few minutes. "
          "If it keeps happening, the server's email settings need fixing.";
    }
    if (lower.contains('rate limit') || lower.contains('too many') || lower.contains('security purposes')) {
      return 'Too many tries. Wait a minute, then try again.';
    }
    if (lower.contains('email address') && lower.contains('invalid')) return "That email address doesn't look right.";
    if (lower.contains('email not confirmed')) return 'Confirm your email first. We sent you a code.';
    if (lower.contains('invalid login')) return 'Wrong email or password.';
    if (lower.contains('already registered')) return "There's already an account with this email. Sign in instead.";
    if (lower.contains('token has expired') || lower.contains('otp')) return "That code isn't right, or it expired.";
    if (lower.contains('closed on this server')) return 'Sign-up is closed right now.';
    if (lower.contains('is full')) return 'This server is full. Ask its admin to raise the limit.';
    if (lower.contains('database error saving new user')) return "Sign-up didn't work. It may be closed or full right now.";
    if (lower.contains('password should be')) return 'Passwords need at least 8 characters.';
    if (lower == 'unexpected_failure' || lower.startsWith('{')) return "Something went wrong on the server. Try again in a minute.";
    return m;
  }

  // ─── Account ───────────────────────────────────────────

  @override
  Future<Profile?> restore() async {
    if (_db.auth.currentSession == null) return null;
    try {
      final p = await me();
      _signedIn = true;
      return p;
    } on ApiError catch (e) {
      if (e.offline) rethrow;
      await _db.auth.signOut();
      return null;
    }
  }

  Future<AuthResult> _after(sb.AuthResponse r, String email) async {
    if (r.session == null) return AuthResult(needsEmailCode: true, email: email);
    final p = await me();
    _signedIn = true;
    return AuthResult(profile: p, email: email);
  }

  @override
  Future<AuthResult> signUp({required String email, required String password, required String name, required String username}) =>
      _auth(() async {
        if (!await usernameAvailable(username)) throw const ApiError('That username is taken. Try another one.');
        final r = await _db.auth.signUp(email: email, password: password, data: {'name': name, 'username': username});
        return _after(r, email);
      });

  @override
  Future<AuthResult> signIn(String email, String password) => _auth(() async {
        try {
          final r = await _db.auth.signInWithPassword(email: email, password: password);
          return await _after(r, email);
        } on sb.AuthException catch (e) {
          if (e.message.toLowerCase().contains('not confirmed')) {
            await _db.auth.resend(type: sb.OtpType.signup, email: email);
            return AuthResult(needsEmailCode: true, email: email);
          }
          rethrow;
        }
      });

  @override
  Future<AuthResult> signInWithGoogle({required String idToken, String? accessToken}) => _auth(() async {
        final r = await _db.auth.signInWithIdToken(provider: sb.OAuthProvider.google, idToken: idToken, accessToken: accessToken);
        return _after(r, r.user?.email ?? '');
      });

  @override
  Future<void> signOut() async {
    _signedIn = false;
    await disconnectLive();
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  @override
  Future<void> sendVerification(String email) => _auth(() => _db.auth.resend(type: sb.OtpType.signup, email: email));

  @override
  Future<Profile> verifyEmail(String email, String code) => _auth(() async {
        await _db.auth.verifyOTP(type: sb.OtpType.signup, email: email, token: code.trim());
        final p = await me();
        _signedIn = true;
        return p;
      });

  @override
  Future<void> sendPasswordReset(String email) => _auth(() => _db.auth.resetPasswordForEmail(email));

  @override
  Future<void> resetPassword(String email, String code, String newPassword) => _auth(() async {
        await _db.auth.verifyOTP(type: sb.OtpType.recovery, email: email, token: code.trim());
        await _db.auth.updateUser(sb.UserAttributes(password: newPassword));
        // Same as the FastAPI build: sign in again with the new password.
        await _db.auth.signOut();
      });

  @override
  Future<void> changePassword(String oldPassword, String newPassword) => _auth(() async {
        final email = _db.auth.currentUser?.email ?? '';
        try {
          await _db.auth.signInWithPassword(email: email, password: oldPassword);
        } on sb.AuthException {
          throw const ApiError("Your current password isn't right.");
        }
        await _db.auth.updateUser(sb.UserAttributes(password: newPassword));
      });

  @override
  Future<bool> usernameAvailable(String username) async =>
      (await _rpc('username_available', {'p_username': username})) == true;

  @override
  Future<ServerConfig> config() async {
    final j = await _obj('app_config');
    return ServerConfig.fromJson({...j, 'name': 'Supabase', 'google_client_ids': const ['configured-in-app']});
  }

  // ─── People ────────────────────────────────────────────

  @override
  Future<Profile> me() async {
    final j = await _obj('me');
    j['email_verified'] = _db.auth.currentUser?.emailConfirmedAt != null;
    return Profile.fromJson(j);
  }

  @override
  Future<Profile> updateProfile({String? name, String? username, String? about, String? avatarUrl}) async =>
      Profile.fromJson(await _obj('update_profile', {
        'p_name': name,
        'p_username': username,
        'p_about': about,
        'p_avatar_url': avatarUrl,
      }));

  @override
  Future<void> deleteAccount() async {
    await _rpc('delete_my_account');
    await signOut();
  }

  @override
  Future<List<Profile>> searchUsers(String query) async =>
      [for (final p in await _list('search_users', {'p_query': query})) _withOnline(Profile.fromJson(p))];

  Profile _withOnline(Profile p) => p.copyWith(online: _online.contains(p.id));

  @override
  Future<UserPage> user(String id) async {
    final page = UserPage.fromJson(await _obj('get_user', {'p_id': id}));
    return UserPage(_withOnline(page.profile), blockedByMe: page.blockedByMe, commonGroups: page.commonGroups);
  }

  @override
  Future<List<Profile>> blockedUsers() async => [for (final p in await _list('my_blocks')) Profile.fromJson(p)];

  @override
  Future<void> block(String userId) async => _rpc('block_user', {'p_id': userId});

  @override
  Future<void> unblock(String userId) async => _rpc('unblock_user', {'p_id': userId});

  // ─── Chats ─────────────────────────────────────────────

  Chat _chat(Map<String, dynamic> j) {
    final c = Chat.fromJson(j);
    final other = c.otherUser;
    return other == null ? c : c.copyWith(otherUser: _withOnline(other));
  }

  @override
  Future<List<Chat>> chats() async => [for (final c in await _list('my_chats')) _chat(c)];

  @override
  Future<Chat> chat(String chatId) async => _chat(await _obj('chat_details', {'p_chat': chatId}));

  @override
  Future<Chat> startDirect(String userId) async => _chat(await _obj('start_direct', {'p_user': userId}));

  @override
  Future<Chat> createGroup({required String name, String description = '', String? imageUrl,
          required List<String> memberIds, bool adminOnly = false}) async =>
      _chat(await _obj('create_group', {
        'p_name': name,
        'p_description': description,
        'p_image_url': imageUrl,
        'p_member_ids': memberIds,
        'p_admin_only': adminOnly,
      }));

  @override
  Future<Chat> updateGroup(String chatId, {String? name, String? description, String? imageUrl, bool? adminOnly}) async =>
      _chat(await _obj('update_group', {
        'p_chat': chatId,
        'p_name': name,
        'p_description': description,
        'p_image_url': imageUrl,
        'p_admin_only': adminOnly,
      }));

  @override
  Future<void> deleteChat(String chatId) async => _rpc('delete_chat', {'p_chat': chatId});

  @override
  Future<Chat> addMembers(String chatId, List<String> userIds) async =>
      _chat(await _obj('add_members', {'p_chat': chatId, 'p_user_ids': userIds}));

  @override
  Future<Chat> setRole(String chatId, String userId, String role) async =>
      _chat(await _obj('set_member_role', {'p_chat': chatId, 'p_user': userId, 'p_role': role}));

  @override
  Future<Chat?> removeMember(String chatId, String userId) async {
    final r = await _rpc('remove_member', {'p_chat': chatId, 'p_user': userId});
    return r is Map ? _chat(Map<String, dynamic>.from(r)) : null;
  }

  @override
  Future<void> setMuted(String chatId, bool muted) async => _rpc('set_muted', {'p_chat': chatId, 'p_muted': muted});

  @override
  Future<void> markRead(String chatId, int seq) async => _rpc('mark_read', {'p_chat': chatId, 'p_seq': seq});

  @override
  Future<void> markDelivered(String chatId, int seq) async => _rpc('mark_delivered', {'p_chat': chatId, 'p_seq': seq});

  @override
  Future<void> markAllDelivered() async => _rpc('mark_all_delivered');

  // ─── Messages ──────────────────────────────────────────

  @override
  Future<List<ChatMessage>> messages(String chatId, {int? beforeSeq, int? afterSeq, int limit = 50}) async => [
        for (final m in await _list('get_messages', {
          'p_chat': chatId,
          'p_before': beforeSeq,
          'p_after': afterSeq,
          'p_limit': limit,
        }))
          ChatMessage.fromJson(m)
      ];

  @override
  Future<List<ChatMessage>> pinned(String chatId) async =>
      [for (final m in await _list('pinned_messages', {'p_chat': chatId})) ChatMessage.fromJson(m)];

  @override
  Future<ChatMessage> send(String chatId, {required String clientId, required MessageKind kind, String body = '',
          Map<String, dynamic>? payload, String? replyToId}) async =>
      ChatMessage.fromJson(await _obj('send_message', {
        'p_chat': chatId,
        'p_client_id': clientId,
        'p_kind': kind.name,
        'p_body': body,
        'p_payload': payload,
        'p_reply_to': replyToId,
      }));

  @override
  Future<ChatMessage> edit(String messageId, String body) async =>
      ChatMessage.fromJson(await _obj('edit_message', {'p_id': messageId, 'p_body': body}));

  @override
  Future<ChatMessage> delete(String messageId) async => ChatMessage.fromJson(await _obj('delete_message', {'p_id': messageId}));

  @override
  Future<ChatMessage> pin(String messageId, bool pinned) async =>
      ChatMessage.fromJson(await _obj('pin_message', {'p_id': messageId, 'p_pinned': pinned}));

  @override
  Future<ChatMessage> react(String messageId, String emoji) async =>
      ChatMessage.fromJson(await _obj('react', {'p_id': messageId, 'p_emoji': emoji}));

  @override
  Future<ChatMessage> unreact(String messageId) async => ChatMessage.fromJson(await _obj('unreact', {'p_id': messageId}));

  @override
  Future<String> uploadImage(Uint8List bytes, {required String contentType, String extension = 'jpg'}) async {
    final uid = _uid;
    if (uid == null) throw const ApiError('Not signed in.', status: 401);
    final path = '$uid/${const UuidV4().generate()}.$extension';
    try {
      await _db.storage.from('media').uploadBinary(path, bytes,
          fileOptions: sb.FileOptions(contentType: contentType, upsert: false));
    } on sb.StorageException catch (e) {
      throw ApiError("The picture couldn't be uploaded: ${e.message}");
    } catch (_) {
      throw const ApiError("You're offline, or Supabase can't be reached.", offline: true);
    }
    return _db.storage.from('media').getPublicUrl(path);
  }

  // ─── Push, sync, announcements ─────────────────────────

  @override
  Future<void> registerDevice(String token, String platform) async =>
      _rpc('register_device', {'p_token': token, 'p_platform': platform});

  @override
  Future<void> unregisterDevice(String token) async => _rpc('unregister_device', {'p_token': token});

  @override
  Future<SyncPull> syncPull(int since) async =>
      SyncPull.fromJson(await _obj('sync_pull', {'p_since': since, 'p_limit': 500}));

  @override
  Future<SyncPushResult> syncPush(List<Map<String, dynamic>> items) async =>
      SyncPushResult.fromJson(await _obj('sync_push', {'p_items': items}));

  @override
  Future<List<Announcement>> announcements() async =>
      [for (final a in await _list('announcements_list')) Announcement.fromJson(a)];

  // ─── Admin ─────────────────────────────────────────────

  @override
  Future<AdminStats> adminStats() async {
    final s = await _obj('admin_stats');
    s['online'] = _online.length;
    return AdminStats.fromJson(s);
  }

  @override
  Future<List<Profile>> adminUsers(String query) async =>
      [for (final p in await _list('admin_users', {'p_query': query})) _withOnline(Profile.fromJson(p))];

  @override
  Future<Profile> adminUpdateUser(String userId, {bool? disabled, bool? admin}) async =>
      Profile.fromJson(await _obj('admin_update_user', {'p_id': userId, 'p_disabled': disabled, 'p_admin': admin}));

  @override
  Future<AppSettingsInfo> adminSettings() async => AppSettingsInfo.fromJson(await _obj('admin_settings'));

  @override
  Future<AppSettingsInfo> adminUpdateSettings({bool? signupEnabled, int? userLimit, String? maintenanceMessage}) async =>
      AppSettingsInfo.fromJson(await _obj('admin_update_settings', {
        'p_signup_enabled': signupEnabled,
        'p_user_limit': userLimit,
        'p_maintenance_message': maintenanceMessage,
      }));

  @override
  Future<Announcement> announce({required String title, String body = '', String kind = 'info'}) async =>
      Announcement.fromJson(await _obj('admin_announce', {'p_title': title, 'p_body': body, 'p_kind': kind}));

  @override
  Future<Announcement> setAnnouncementActive(String id, bool active) async =>
      Announcement.fromJson(await _obj('admin_set_announcement', {'p_id': id, 'p_active': active}));

  // ─── Live (Realtime) ───────────────────────────────────

  final _events = StreamController<LiveEvent>.broadcast();
  final _status = StreamController<bool>.broadcast();
  sb.RealtimeChannel? _changes;
  sb.RealtimeChannel? _presence;
  final _typingChannels = <String, sb.RealtimeChannel>{};
  Set<String> _online = {};
  bool _connected = false;
  bool _everConnected = false;

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  bool get liveConnected => _connected;

  @override
  Stream<bool> get liveStatus => _status.stream;

  @override
  Set<String> get onlineUsers => _online;

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _status.add(value);
    if (value) {
      if (_everConnected) _events.add(const ReconnectedEvent());
      _everConnected = true;
    }
  }

  /// A database row (snake_case columns) in the API's message shape.
  static Map<String, dynamic> _messageRow(Map<String, dynamic> r) {
    final deleted = r['deleted_at'] != null;
    return {
      'id': r['id'],
      'seq': r['seq'],
      'chat_id': r['chat_id'],
      'sender_id': r['sender_id'],
      'client_id': r['client_id'],
      'kind': r['kind'],
      'body': deleted ? '' : r['body'],
      'payload': deleted ? null : r['payload'],
      'reply_to': deleted ? null : r['reply_preview'],
      'reactions': deleted ? const {} : (r['reactions'] ?? const {}),
      'pinned': r['pinned_at'] != null && !deleted,
      'edited': r['edited_at'] != null,
      'deleted': deleted,
      'created_at': r['created_at'],
    };
  }

  @override
  Future<void> connectLive() async {
    final uid = _uid;
    if (uid == null || _changes != null) return;
    // Row-level security makes sure each person only gets their own chats.
    final ch = _db.channel('codenote-live-$uid');
    ch
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) => _events.add(MessageEvent(ChatMessage.fromJson(_messageRow(p.newRecord)), isNew: true)),
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (p) => _events.add(MessageEvent(ChatMessage.fromJson(_messageRow(p.newRecord)), isNew: false)),
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_members',
          callback: (p) {
            final row = p.eventType == sb.PostgresChangeEvent.delete ? p.oldRecord : p.newRecord;
            final chatId = '${row['chat_id']}';
            final userId = '${row['user_id']}';
            if (p.eventType == sb.PostgresChangeEvent.delete) {
              _events.add(userId == uid ? ChatRemovedEvent(chatId) : ChatChangedEvent(chatId));
            } else if (p.eventType == sb.PostgresChangeEvent.insert) {
              _events.add(ChatChangedEvent(chatId));
            } else {
              _events.add(ReceiptEvent(
                chatId: chatId,
                userId: userId,
                readSeq: (row['read_seq'] as num?)?.toInt() ?? 0,
                deliveredSeq: (row['delivered_seq'] as num?)?.toInt() ?? 0,
              ));
              final old = p.oldRecord;
              if (userId == uid && (old['hidden'] != row['hidden'] || old['muted'] != row['muted'] || old['role'] != row['role'])) {
                _events.add(ChatChangedEvent(chatId));
              } else if (userId != uid && old['role'] != row['role']) {
                _events.add(ChatChangedEvent(chatId));
              }
            }
          },
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'chats',
          callback: (p) {
            if (p.eventType == sb.PostgresChangeEvent.delete) {
              _events.add(ChatRemovedEvent('${p.oldRecord['id']}'));
            } else {
              _events.add(ChatChangedEvent('${p.newRecord['id']}'));
            }
          },
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'synced_items',
          callback: (p) => _events.add(SyncEvent((p.newRecord['rev'] as num?)?.toInt() ?? 0)),
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'announcements',
          callback: (p) => _events.add(AnnouncementEvent(Announcement.fromJson({
            ...p.newRecord,
            'created_at': p.newRecord['created_at'],
          }))),
        )
        .subscribe((status, error) {
          _setConnected(status == sb.RealtimeSubscribeStatus.subscribed);
        });
    _changes = ch;

    // Who's online: everyone signed in joins one presence channel.
    final pr = _db.channel('codenote-online');
    pr.onPresenceSync((_) {
      final now = <String>{};
      for (final state in pr.presenceState()) {
        for (final presence in state.presences) {
          final id = presence.payload['user_id'];
          if (id is String) now.add(id);
        }
      }
      final before = _online;
      _online = now;
      for (final id in now.difference(before)) {
        _events.add(PresenceEvent(id, true, DateTime.now()));
      }
      for (final id in before.difference(now)) {
        _events.add(PresenceEvent(id, false, DateTime.now()));
      }
    }).subscribe((status, error) async {
      if (status == sb.RealtimeSubscribeStatus.subscribed) {
        await pr.track({'user_id': uid});
      }
    });
    _presence = pr;
    for (final chatId in _typingChannels.keys.toList()) {
      _typingChannels.remove(chatId);
      watchChat(chatId);
    }
  }

  @override
  Future<void> disconnectLive() async {
    for (final c in [_changes, _presence, ..._typingChannels.values]) {
      if (c != null) await _db.removeChannel(c);
    }
    _changes = null;
    _presence = null;
    _typingChannels.clear();
    _online = {};
    _setConnected(false);
  }

  @override
  void watchChat(String chatId) {
    if (_typingChannels.containsKey(chatId) || _uid == null) return;
    final ch = _db.channel('typing:$chatId');
    ch.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final user = payload['user_id'];
        if (user is String && user != _uid) _events.add(TypingEvent(chatId, user));
      },
    ).subscribe();
    _typingChannels[chatId] = ch;
  }

  @override
  void unwatchChat(String chatId) {
    final ch = _typingChannels.remove(chatId);
    if (ch != null) _db.removeChannel(ch);
  }

  @override
  void sendTyping(String chatId) {
    final ch = _typingChannels[chatId];
    final uid = _uid;
    if (ch == null || uid == null) return;
    ch.sendBroadcastMessage(event: 'typing', payload: {'user_id': uid});
  }

  void dispose() => _authSub.cancel();
}
