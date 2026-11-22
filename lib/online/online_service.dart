import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/services/log_service.dart';
import 'backend/backend.dart';
import 'backend/fastapi_backend.dart';
import 'backend/supabase_backend.dart';
import 'chat/chat_store.dart';
import 'models.dart';
import 'online_config.dart';
import 'push/push_service.dart';
import 'sync/notes_sync.dart';

enum OnlineStage {
  /// Starting up.
  loading,

  /// FastAPI build: no server address yet.
  needsServer,

  /// Not signed in (the person can still use notes on this device).
  signedOut,

  /// Signed in, but the email still needs its code.
  needsEmailCode,

  /// Signed in.
  signedIn,
}

/// Holds the backend, who's signed in, and starts chat, sync and push.
class OnlineService extends ChangeNotifier {
  OnlineService._();
  static final instance = OnlineService._();

  static const _boxName = 'online';
  static const _serverKey = 'server_url';
  static const _serverNameKey = 'server_name';
  static const _meKey = 'me';
  static const _skippedKey = 'skipped';

  late Box _box;
  Backend? _backend;
  OnlineStage _stage = OnlineStage.loading;
  Profile? _me;
  String? _pendingEmail;
  String? _signedOutReason;

  OnlineStage get stage => _stage;
  Profile? get me => _me;
  bool get signedIn => _stage == OnlineStage.signedIn;
  String? get pendingEmail => _pendingEmail;

  /// Why the last session ended by itself, shown once on the sign-in screen.
  String? takeSignedOutReason() {
    final r = _signedOutReason;
    _signedOutReason = null;
    return r;
  }

  /// The backend. Only use after [init], and not while [stage] is needsServer.
  Backend get backend => _backend!;
  bool get hasBackend => _backend != null;

  String? get serverUrl => _box.get(_serverKey) as String?;
  String get serverName => (_box.get(_serverNameKey) as String?) ?? OnlineConfig.backendLabel;

  /// True if the person chose "Use without an account" on this device.
  bool get skipped => _box.get(_skippedKey) == true;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    try {
      if (OnlineConfig.isSupabase) {
        if (OnlineConfig.supabaseUrl.isEmpty || OnlineConfig.supabaseAnonKey.isEmpty) {
          LogService().log('Online: this build has no SUPABASE_URL / SUPABASE_ANON_KEY.');
          _set(OnlineStage.signedOut);
          return;
        }
        await sb.Supabase.initialize(url: OnlineConfig.supabaseUrl, anonKey: OnlineConfig.supabaseAnonKey);
        _backend = SupabaseBackend(sb.Supabase.instance.client);
      } else {
        final url = serverUrl;
        if (url == null || url.isEmpty) {
          _set(OnlineStage.needsServer);
          return;
        }
        _backend = FastApiBackend(baseUrl: url, box: _box);
      }
      _backend!.onSignedOut = _onSessionEnded;
      await _restore();
    } catch (e) {
      LogService().log('Online: start failed: $e');
      _set(_backend == null && OnlineConfig.isFastApi ? OnlineStage.needsServer : OnlineStage.signedOut);
    }
  }

  Future<void> _restore() async {
    try {
      final p = await backend.restore();
      if (p == null) {
        _set(OnlineStage.signedOut);
        return;
      }
      await _signedIn(p);
    } on ApiError catch (e) {
      if (!e.offline) rethrow;
      // Offline at start: keep the saved account and connect later.
      final saved = _box.get(_meKey) as String?;
      if (saved == null) {
        _set(OnlineStage.signedOut);
        return;
      }
      _me = Profile.fromJson(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      _set(OnlineStage.signedIn);
      _startServices();
      _retryRestore();
    }
  }

  Timer? _restoreTimer;
  void _retryRestore() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 15), () async {
      try {
        final p = await backend.restore();
        if (p == null) {
          await _endSession('You were signed out.');
        } else {
          _me = p;
          notifyListeners();
          await backend.connectLive();
        }
      } catch (_) {
        _retryRestore();
      }
    });
  }

  void _set(OnlineStage stage) {
    _stage = stage;
    notifyListeners();
  }

  // ─── FastAPI: server address ───────────────────────────

  /// Checks [url] and uses it. Throws [ApiError] with what's wrong.
  Future<void> setServer(String url) async {
    var clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) clean = 'https://$clean';
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    final name = await FastApiBackend.check(clean);
    if (_backend != null && signedIn) await signOut();
    await _box.put(_serverKey, clean);
    await _box.put(_serverNameKey, name);
    _backend = FastApiBackend(baseUrl: clean, box: _box)..onSignedOut = _onSessionEnded;
    await _restore();
  }

  // ─── Sign in and out ───────────────────────────────────

  /// Finishes a sign-in, sign-up or Google sign-in.
  Future<void> handleAuth(AuthResult r) async {
    if (r.needsEmailCode || r.profile == null) {
      _pendingEmail = r.email;
      _set(OnlineStage.needsEmailCode);
      return;
    }
    if (!r.profile!.emailVerified && OnlineConfig.isFastApi && (await _needsVerification())) {
      _pendingEmail = r.profile!.email ?? r.email;
      _me = r.profile;
      _set(OnlineStage.needsEmailCode);
      return;
    }
    await _signedIn(r.profile!);
  }

  Future<bool> _needsVerification() async {
    try {
      return (await backend.config()).emailVerification;
    } catch (_) {
      return false;
    }
  }

  Future<void> verifyEmail(String code) async {
    final p = await backend.verifyEmail(_pendingEmail ?? '', code);
    _pendingEmail = null;
    await _signedIn(p);
  }

  Future<void> _signedIn(Profile p) async {
    _me = p;
    await _box.put(_meKey, jsonEncode(_profileJson(p)));
    await _box.put(_skippedKey, false);
    _set(OnlineStage.signedIn);
    _startServices();
  }

  void _startServices() {
    ChatStore.instance.start(backend, _me!.id);
    NotesSync.instance.start(backend);
    PushService.instance.start(backend);
    backend.connectLive();
  }

  /// "Use without an account": notes stay on this device until sign-in.
  Future<void> skipForNow() async {
    await _box.put(_skippedKey, true);
    notifyListeners();
  }

  /// The FastAPI build again asks for a server address.
  Future<void> forgetServer() async {
    if (signedIn) await signOut();
    await _box.delete(_serverKey);
    await _box.delete(_serverNameKey);
    _backend = null;
    _set(OnlineStage.needsServer);
  }

  Future<void> signOut() async {
    await PushService.instance.stop();
    await _endLocal();
    try {
      await backend.signOut();
    } catch (_) {}
    _set(OnlineStage.signedOut);
  }

  Future<void> deleteAccount() async {
    await PushService.instance.stop();
    await backend.deleteAccount();
    await _endLocal();
    _set(OnlineStage.signedOut);
  }

  Future<void> _endLocal() async {
    _restoreTimer?.cancel();
    ChatStore.instance.stop();
    NotesSync.instance.stop();
    _me = null;
    _pendingEmail = null;
    await _box.delete(_meKey);
  }

  void _onSessionEnded(String reason) {
    _endSession(reason);
  }

  Future<void> _endSession(String reason) async {
    if (_stage != OnlineStage.signedIn && _stage != OnlineStage.needsEmailCode) return;
    _signedOutReason = reason;
    await PushService.instance.stop();
    await _endLocal();
    try {
      await backend.disconnectLive();
    } catch (_) {}
    _set(OnlineStage.signedOut);
  }

  /// After the profile changes on this device.
  Future<void> updateMe(Profile p) async {
    _me = p;
    await _box.put(_meKey, jsonEncode(_profileJson(p)));
    notifyListeners();
  }

  static Map<String, dynamic> _profileJson(Profile p) => {
        'id': p.id,
        'name': p.name,
        'username': p.username,
        'avatar_url': p.avatarUrl,
        'about': p.about,
        'email': p.email,
        'email_verified': p.emailVerified,
        'is_admin': p.isAdmin,
      };
}
