import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models.dart';
import 'backend.dart';

/// Talks to the CodeNote server in server/ (FastAPI).
class FastApiBackend extends Backend {
  FastApiBackend({required String baseUrl, required Box box})
      : _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _box = box {
    _access = _box.get(_accessKey) as String?;
    _refresh = _box.get(_refreshKey) as String?;
  }

  final String _base;
  final Box _box;
  final _client = http.Client();
  static const _accessKey = 'fa_access';
  static const _refreshKey = 'fa_refresh';
  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  String get baseUrl => _base;

  /// Checks that [url] is a CodeNote server. Returns its name.
  static Future<String> check(String url) async {
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final http.Response r;
    try {
      r = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const ApiError("The server didn't answer in time. Check the address and that the server is running.", offline: true);
    } catch (_) {
      throw const ApiError("Couldn't reach that address. Check it, and that this device is online.", offline: true);
    }
    Map<String, dynamic>? body;
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode != 200 || body?['app'] != 'codenote') {
      throw const ApiError("That address answers, but it isn't a CodeNote server.");
    }
    return (body?['name'] as String?)?.trim().isNotEmpty == true ? body!['name'] as String : 'CodeNote server';
  }

  // ─── Requests ──────────────────────────────────────────

  Future<void> _saveSession(Map<String, dynamic> s) async {
    _access = s['access_token'] as String?;
    _refresh = s['refresh_token'] as String?;
    await _box.put(_accessKey, _access);
    await _box.put(_refreshKey, _refresh);
  }

  Future<void> _clearSession() async {
    _access = null;
    _refresh = null;
    await _box.delete(_accessKey);
    await _box.delete(_refreshKey);
  }

  /// Gets new tokens with the refresh token (once, even if many requests
  /// ask at the same time).
  Future<bool> _renew() => _refreshing ??= () async {
        try {
          final token = _refresh;
          if (token == null) return false;
          final r = await _client
              .post(Uri.parse('$_base/auth/refresh'),
                  headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh_token': token}))
              .timeout(const Duration(seconds: 20));
          if (r.statusCode == 200) {
            await _saveSession(jsonDecode(r.body) as Map<String, dynamic>);
            return true;
          }
          if (r.statusCode == 401 || r.statusCode == 403) {
            final reason = _detail(r) ?? 'You were signed out.';
            await _clearSession();
            onSignedOut?.call(reason);
          }
          return false;
        } catch (_) {
          return false; // offline: keep the session, try again later
        } finally {
          _refreshing = null;
        }
      }();

  static String? _detail(http.Response r) {
    try {
      final d = (jsonDecode(r.body) as Map)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return null;
  }

  Future<dynamic> _call(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true, bool retried = false}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (auth && _access != null) request.headers['Authorization'] = 'Bearer $_access';
    final http.Response r;
    try {
      r = await http.Response.fromStream(await _client.send(request).timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw const ApiError('The server is taking too long. Try again in a moment.', offline: true);
    } catch (_) {
      throw const ApiError("You're offline, or the server can't be reached.", offline: true);
    }
    if (r.statusCode == 401 && auth && !retried && _refresh != null) {
      if (await _renew()) return _call(method, path, body: body, query: query, auth: auth, retried: true);
    }
    if (r.statusCode >= 400) {
      throw ApiError(_detail(r) ?? 'Something went wrong (${r.statusCode}).', status: r.statusCode);
    }
    if (r.body.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<Map<String, dynamic>> _obj(String method, String path, {Object? body, Map<String, String>? query, bool auth = true}) async =>
      Map<String, dynamic>.from((await _call(method, path, body: body, query: query, auth: auth)) as Map);

  Future<List<Map<String, dynamic>>> _list(String path, {Map<String, String>? query}) async =>
      [for (final x in (await _call('GET', path, query: query)) as List) Map<String, dynamic>.from(x as Map)];

  // ─── Account ───────────────────────────────────────────

  @override
  Future<Profile?> restore() async {
    if (_access == null && _refresh == null) return null;
    try {
      return Profile.fromJson(await _obj('GET', '/me'));
    } on ApiError catch (e) {
      if (e.offline) rethrow;
      await _clearSession();
      return null;
    }
  }

  Future<AuthResult> _session(String path, Map<String, dynamic> body, String email) async {
    final s = await _obj('POST', path, body: body, auth: false);
    await _saveSession(s);
    return AuthResult(profile: Profile.fromJson(Map<String, dynamic>.from(s['user'] as Map)), email: email);
  }

  @override
  Future<AuthResult> signUp({required String email, required String password, required String name, required String username}) =>
      _session('/auth/signup', {'email': email, 'password': password, 'name': name, 'username': username}, email);

  @override
  Future<AuthResult> signIn(String email, String password) =>
      _session('/auth/login', {'email': email, 'password': password}, email);

  @override
  Future<AuthResult> signInWithGoogle({required String idToken, String? accessToken}) =>
      _session('/auth/google', {'id_token': idToken}, '');

  @override
  Future<void> signOut() async {
    final token = _refresh;
    await disconnectLive();
    if (token != null) {
      try {
        await _call('POST', '/auth/logout', body: {'refresh_token': token}, auth: false);
      } catch (_) {}
    }
    await _clearSession();
  }

  @override
  Future<void> sendVerification(String email) async => _call('POST', '/auth/verify/send');

  @override
  Future<Profile> verifyEmail(String email, String code) async =>
      Profile.fromJson(await _obj('POST', '/auth/verify', body: {'code': code}));

  @override
  Future<void> sendPasswordReset(String email) async =>
      _call('POST', '/auth/password/forgot', body: {'email': email}, auth: false);

  @override
  Future<void> resetPassword(String email, String code, String newPassword) async =>
      _call('POST', '/auth/password/reset', body: {'email': email, 'code': code, 'password': newPassword}, auth: false);

  @override
  Future<void> changePassword(String oldPassword, String newPassword) async {
    final s = await _obj('POST', '/auth/password/change', body: {'old_password': oldPassword, 'password': newPassword});
    await _saveSession(s);
  }

  @override
  Future<bool> usernameAvailable(String username) async {
    final path = _access == null ? '/users/username-free' : '/users/username-available';
    final r = await _obj('GET', path, query: {'username': username}, auth: _access != null);
    return r['available'] == true;
  }

  @override
  Future<ServerConfig> config() async => ServerConfig.fromJson(await _obj('GET', '/config', auth: false));

  // ─── People ────────────────────────────────────────────

  @override
  Future<Profile> me() async => Profile.fromJson(await _obj('GET', '/me'));

  @override
  Future<Profile> updateProfile({String? name, String? username, String? about, String? avatarUrl}) async =>
      Profile.fromJson(await _obj('PATCH', '/me', body: {
        if (name != null) 'name': name,
        if (username != null) 'username': username,
        if (about != null) 'about': about,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }));

  @override
  Future<void> deleteAccount() async {
    await _call('DELETE', '/me');
    await disconnectLive();
    await _clearSession();
  }

  @override
  Future<List<Profile>> searchUsers(String query) async =>
      [for (final p in await _list('/users/search', query: {'q': query})) Profile.fromJson(p)];

  @override
  Future<UserPage> user(String id) async => UserPage.fromJson(await _obj('GET', '/users/$id'));

  @override
  Future<List<Profile>> blockedUsers() async => [for (final p in await _list('/me/blocks')) Profile.fromJson(p)];

  @override
  Future<void> block(String userId) async => _call('PUT', '/users/$userId/block');

  @override
  Future<void> unblock(String userId) async => _call('DELETE', '/users/$userId/block');

  // ─── Chats ─────────────────────────────────────────────

  @override
  Future<List<Chat>> chats() async => [for (final c in await _list('/chats')) Chat.fromJson(c)];

  @override
  Future<Chat> chat(String chatId) async => Chat.fromJson(await _obj('GET', '/chats/$chatId'));

  @override
  Future<Chat> startDirect(String userId) async => Chat.fromJson(await _obj('POST', '/chats/direct', body: {'user_id': userId}));

  @override
  Future<Chat> createGroup({required String name, String description = '', String? imageUrl,
          required List<String> memberIds, bool adminOnly = false}) async =>
      Chat.fromJson(await _obj('POST', '/chats/groups', body: {
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'member_ids': memberIds,
        'admin_only': adminOnly,
      }));

  @override
  Future<Chat> updateGroup(String chatId, {String? name, String? description, String? imageUrl, bool? adminOnly}) async =>
      Chat.fromJson(await _obj('PATCH', '/chats/$chatId', body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        if (adminOnly != null) 'admin_only': adminOnly,
      }));

  @override
  Future<void> deleteChat(String chatId) async => _call('DELETE', '/chats/$chatId');

  @override
  Future<Chat> addMembers(String chatId, List<String> userIds) async =>
      Chat.fromJson(await _obj('POST', '/chats/$chatId/members', body: {'user_ids': userIds}));

  @override
  Future<Chat> setRole(String chatId, String userId, String role) async =>
      Chat.fromJson(await _obj('PATCH', '/chats/$chatId/members/$userId', body: {'role': role}));

  @override
  Future<Chat?> removeMember(String chatId, String userId) async {
    final r = await _call('DELETE', '/chats/$chatId/members/$userId');
    return r is Map && r['id'] != null ? Chat.fromJson(Map<String, dynamic>.from(r)) : null;
  }

  @override
  Future<void> setMuted(String chatId, bool muted) async => _call('PATCH', '/chats/$chatId/me', body: {'muted': muted});

  @override
  Future<void> markRead(String chatId, int seq) async => _call('POST', '/chats/$chatId/read', body: {'seq': seq});

  @override
  Future<void> markDelivered(String chatId, int seq) async => _call('POST', '/chats/$chatId/delivered', body: {'seq': seq});

  @override
  Future<void> markAllDelivered() async => _call('POST', '/chats/delivered-all');

  // ─── Messages ──────────────────────────────────────────

  @override
  Future<List<ChatMessage>> messages(String chatId, {int? beforeSeq, int? afterSeq, int limit = 50}) async => [
        for (final m in await _list('/chats/$chatId/messages', query: {
          if (beforeSeq != null) 'before_seq': '$beforeSeq',
          if (afterSeq != null) 'after_seq': '$afterSeq',
          'limit': '$limit',
        }))
          ChatMessage.fromJson(m)
      ];

  @override
  Future<List<ChatMessage>> pinned(String chatId) async =>
      [for (final m in await _list('/chats/$chatId/pinned')) ChatMessage.fromJson(m)];

  @override
  Future<ChatMessage> send(String chatId, {required String clientId, required MessageKind kind, String body = '',
          Map<String, dynamic>? payload, String? replyToId}) async =>
      ChatMessage.fromJson(await _obj('POST', '/chats/$chatId/messages', body: {
        'client_id': clientId,
        'kind': kind.name,
        'body': body,
        'payload': payload,
        'reply_to_id': replyToId,
      }));

  @override
  Future<ChatMessage> edit(String messageId, String body) async =>
      ChatMessage.fromJson(await _obj('PATCH', '/messages/$messageId', body: {'body': body}));

  @override
  Future<ChatMessage> delete(String messageId) async => ChatMessage.fromJson(await _obj('DELETE', '/messages/$messageId'));

  @override
  Future<ChatMessage> pin(String messageId, bool pinned) async =>
      ChatMessage.fromJson(await _obj('PUT', '/messages/$messageId/pin', body: {'pinned': pinned}));

  @override
  Future<ChatMessage> react(String messageId, String emoji) async =>
      ChatMessage.fromJson(await _obj('PUT', '/messages/$messageId/reaction', body: {'emoji': emoji}));

  @override
  Future<ChatMessage> unreact(String messageId) async =>
      ChatMessage.fromJson(await _obj('DELETE', '/messages/$messageId/reaction'));

  @override
  Future<String> uploadImage(Uint8List bytes, {required String contentType, String extension = 'jpg'}) async {
    Future<http.Response> attempt() async {
      final request = http.MultipartRequest('POST', Uri.parse('$_base/files'));
      if (_access != null) request.headers['Authorization'] = 'Bearer $_access';
      request.files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: 'image.$extension', contentType: _mediaType(contentType)));
      return http.Response.fromStream(await _client.send(request).timeout(const Duration(seconds: 120)));
    }

    http.Response r;
    try {
      r = await attempt();
      if (r.statusCode == 401 && await _renew()) r = await attempt();
    } on TimeoutException {
      throw const ApiError('The upload took too long. Try a smaller picture.', offline: true);
    } catch (e) {
      if (e is ApiError) rethrow;
      throw const ApiError("You're offline, or the server can't be reached.", offline: true);
    }
    if (r.statusCode >= 400) throw ApiError(_detail(r) ?? "The picture couldn't be uploaded.", status: r.statusCode);
    return (jsonDecode(r.body) as Map)['url'] as String;
  }

  static MediaType _mediaType(String contentType) {
    final parts = contentType.split('/');
    return MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg');
  }

  // ─── Push, sync, announcements ─────────────────────────

  @override
  Future<void> registerDevice(String token, String platform) async =>
      _call('POST', '/devices', body: {'token': token, 'platform': platform});

  @override
  Future<void> unregisterDevice(String token) async =>
      _call('DELETE', '/devices', body: {'token': token, 'platform': 'android'});

  @override
  Future<SyncPull> syncPull(int since) async => SyncPull.fromJson(await _obj('GET', '/sync', query: {'since': '$since'}));

  @override
  Future<SyncPushResult> syncPush(List<Map<String, dynamic>> items) async =>
      SyncPushResult.fromJson(await _obj('POST', '/sync', body: {'items': items}));

  @override
  Future<List<Announcement>> announcements() async =>
      [for (final a in await _list('/announcements')) Announcement.fromJson(a)];

  // ─── Admin ─────────────────────────────────────────────

  @override
  Future<AdminStats> adminStats() async => AdminStats.fromJson(await _obj('GET', '/admin/stats'));

  @override
  Future<List<Profile>> adminUsers(String query) async =>
      [for (final p in await _list('/admin/users', query: {'q': query})) Profile.fromJson(p)];

  @override
  Future<Profile> adminUpdateUser(String userId, {bool? disabled, bool? admin}) async =>
      Profile.fromJson(await _obj('PATCH', '/admin/users/$userId', body: {
        if (disabled != null) 'is_disabled': disabled,
        if (admin != null) 'is_admin': admin,
      }));

  @override
  Future<AppSettingsInfo> adminSettings() async => AppSettingsInfo.fromJson(await _obj('GET', '/admin/settings'));

  @override
  Future<AppSettingsInfo> adminUpdateSettings({bool? signupEnabled, int? userLimit, String? maintenanceMessage}) async =>
      AppSettingsInfo.fromJson(await _obj('PATCH', '/admin/settings', body: {
        if (signupEnabled != null) 'signup_enabled': signupEnabled,
        if (userLimit != null) 'user_limit': userLimit,
        if (maintenanceMessage != null) 'maintenance_message': maintenanceMessage,
      }));

  @override
  Future<Announcement> announce({required String title, String body = '', String kind = 'info'}) async =>
      Announcement.fromJson(await _obj('POST', '/admin/announcements', body: {'title': title, 'body': body, 'kind': kind}));

  @override
  Future<Announcement> setAnnouncementActive(String id, bool active) async =>
      Announcement.fromJson(await _obj('PATCH', '/admin/announcements/$id', body: {'active': active}));

  // ─── Live (WebSocket) ──────────────────────────────────

  final _events = StreamController<LiveEvent>.broadcast();
  final _status = StreamController<bool>.broadcast();
  WebSocketChannel? _socket;
  StreamSubscription? _socketSub;
  Timer? _ping;
  Timer? _retry;
  bool _wanted = false;
  bool _connected = false;
  bool _everConnected = false;
  int _attempt = 0;

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  bool get liveConnected => _connected;

  @override
  Stream<bool> get liveStatus => _status.stream;

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _status.add(value);
  }

  /// True if the access token runs out within a minute (or can't be read).
  bool _accessExpiring() {
    final token = _access;
    if (token == null) return true;
    try {
      final part = token.split('.')[1];
      final data = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part)))) as Map;
      final exp = (data['exp'] as num).toInt();
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp - 60;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> connectLive() async {
    _wanted = true;
    if (_socket != null) return;
    _retry?.cancel();
    if (_accessExpiring() && !await _renew()) {
      if (_refresh == null) return; // signed out
      _scheduleRetry();
      return;
    }
    final wsBase = _base.replaceFirst(RegExp(r'^http'), 'ws');
    final uri = Uri.parse('$wsBase/ws').replace(queryParameters: {'token': _access ?? ''});
    try {
      final socket = WebSocketChannel.connect(uri);
      _socket = socket;
      await socket.ready.timeout(const Duration(seconds: 15));
      _attempt = 0;
      _setConnected(true);
      if (_everConnected) _events.add(const ReconnectedEvent());
      _everConnected = true;
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _sendRaw({'type': 'ping'}));
      _socketSub = socket.stream.listen(
        (data) {
          try {
            final event = liveEventFromJson(Map<String, dynamic>.from(jsonDecode('$data') as Map));
            if (event is AccountDisabledEvent) {
              _clearSession();
              onSignedOut?.call('This account was turned off by an admin.');
            }
            if (event != null) _events.add(event);
          } catch (_) {}
        },
        onDone: () => _lost(socket.closeCode),
        onError: (_) => _lost(null),
        cancelOnError: true,
      );
    } catch (_) {
      _lost(null);
    }
  }

  void _lost(int? code) {
    _ping?.cancel();
    _socketSub?.cancel();
    _socketSub = null;
    _socket = null;
    _setConnected(false);
    if (!_wanted) return;
    if (code == 4003) return; // account turned off
    if (code == 4001) {
      _renew().then((ok) => ok ? connectLive() : _scheduleRetry());
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    // 1, 2, 4, 8… seconds, up to 30, with a little randomness.
    final seconds = min(30, pow(2, _attempt).toInt()) + Random().nextDouble();
    _attempt = min(_attempt + 1, 6);
    _retry = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      if (_wanted) connectLive();
    });
  }

  @override
  Future<void> disconnectLive() async {
    _wanted = false;
    _retry?.cancel();
    _ping?.cancel();
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.sink.close();
    _socket = null;
    _setConnected(false);
  }

  void _sendRaw(Map<String, dynamic> data) {
    try {
      _socket?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  @override
  void sendTyping(String chatId) => _sendRaw({'type': 'typing', 'chat_id': chatId});
}
