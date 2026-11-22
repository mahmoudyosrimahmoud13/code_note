import 'dart:typed_data';

import '../models.dart';

/// A problem the person should see, in plain words.
class ApiError implements Exception {
  const ApiError(this.message, {this.status = 0, this.offline = false});
  final String message;
  final int status;

  /// The server couldn't be reached at all.
  final bool offline;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// After signing up or asking for a code.
class AuthResult {
  const AuthResult({this.profile, this.needsEmailCode = false, required this.email});

  /// Signed in (may still need to confirm the email, see [Profile.emailVerified]).
  final Profile? profile;

  /// A code was emailed; signing in finishes after [Backend.verifyEmail].
  final bool needsEmailCode;
  final String email;
}

/// Everything CodeNote Online asks of its backend. [FastApiBackend] and
/// [SupabaseBackend] both do all of it, with the same rules
/// (docs/online/CONTRACT.md).
abstract class Backend {
  /// Called when the session ends by itself (expired, account turned off).
  void Function(String reason)? onSignedOut;

  // ─── Account ───────────────────────────────────────────

  /// The saved session's profile, or null if signed out.
  Future<Profile?> restore();
  Future<AuthResult> signUp({required String email, required String password, required String name, required String username});
  Future<AuthResult> signIn(String email, String password);
  Future<AuthResult> signInWithGoogle({required String idToken, String? accessToken});
  Future<void> signOut();
  Future<void> sendVerification(String email);
  Future<Profile> verifyEmail(String email, String code);
  Future<void> sendPasswordReset(String email);
  Future<void> resetPassword(String email, String code, String newPassword);
  Future<void> changePassword(String oldPassword, String newPassword);
  Future<bool> usernameAvailable(String username);
  Future<ServerConfig> config();

  // ─── People ────────────────────────────────────────────

  Future<Profile> me();
  Future<Profile> updateProfile({String? name, String? username, String? about, String? avatarUrl});
  Future<void> deleteAccount();
  Future<List<Profile>> searchUsers(String query);
  Future<UserPage> user(String id);
  Future<List<Profile>> blockedUsers();
  Future<void> block(String userId);
  Future<void> unblock(String userId);

  // ─── Chats ─────────────────────────────────────────────

  Future<List<Chat>> chats();
  Future<Chat> chat(String chatId);
  Future<Chat> startDirect(String userId);
  Future<Chat> createGroup({required String name, String description = '', String? imageUrl,
      required List<String> memberIds, bool adminOnly = false});
  Future<Chat> updateGroup(String chatId, {String? name, String? description, String? imageUrl, bool? adminOnly});
  Future<void> deleteChat(String chatId);
  Future<Chat> addMembers(String chatId, List<String> userIds);
  Future<Chat> setRole(String chatId, String userId, String role);

  /// Returns the group after the change, or null when you left.
  Future<Chat?> removeMember(String chatId, String userId);
  Future<void> setMuted(String chatId, bool muted);
  Future<void> markRead(String chatId, int seq);
  Future<void> markDelivered(String chatId, int seq);
  Future<void> markAllDelivered();

  // ─── Messages ──────────────────────────────────────────

  /// Newest first.
  Future<List<ChatMessage>> messages(String chatId, {int? beforeSeq, int? afterSeq, int limit = 50});
  Future<List<ChatMessage>> pinned(String chatId);
  Future<ChatMessage> send(String chatId, {required String clientId, required MessageKind kind, String body = '',
      Map<String, dynamic>? payload, String? replyToId});
  Future<ChatMessage> edit(String messageId, String body);
  Future<ChatMessage> delete(String messageId);
  Future<ChatMessage> pin(String messageId, bool pinned);
  Future<ChatMessage> react(String messageId, String emoji);
  Future<ChatMessage> unreact(String messageId);

  /// Uploads a picture and returns its web address.
  Future<String> uploadImage(Uint8List bytes, {required String contentType, String extension = 'jpg'});

  // ─── Push, sync, announcements ─────────────────────────

  Future<void> registerDevice(String token, String platform);
  Future<void> unregisterDevice(String token);
  Future<SyncPull> syncPull(int since);
  Future<SyncPushResult> syncPush(List<Map<String, dynamic>> items);
  Future<List<Announcement>> announcements();

  // ─── Admin ─────────────────────────────────────────────

  Future<AdminStats> adminStats();
  Future<List<Profile>> adminUsers(String query);
  Future<Profile> adminUpdateUser(String userId, {bool? disabled, bool? admin});
  Future<AppSettingsInfo> adminSettings();
  Future<AppSettingsInfo> adminUpdateSettings({bool? signupEnabled, int? userLimit, String? maintenanceMessage});
  Future<Announcement> announce({required String title, String body = '', String kind = 'info'});
  Future<Announcement> setAnnouncementActive(String id, bool active);

  // ─── Live ──────────────────────────────────────────────

  /// Live updates while connected.
  Stream<LiveEvent> get events;

  /// True while the live connection is up.
  bool get liveConnected;
  Stream<bool> get liveStatus;

  Future<void> connectLive();
  Future<void> disconnectLive();

  /// Tells the others in the chat that you're typing.
  void sendTyping(String chatId);

  /// A conversation was opened or closed (Supabase listens for typing per chat).
  void watchChat(String chatId) {}
  void unwatchChat(String chatId) {}

  /// Who's online, when the backend tracks it separately (Supabase).
  Set<String> get onlineUsers => const {};
}
