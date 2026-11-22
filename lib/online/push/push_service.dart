import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/services/log_service.dart';
import '../backend/backend.dart';
import '../online_config.dart';

/// Push notifications for new messages when the app is closed (Android,
/// iPhone, Mac). Only on when the build has the Firebase settings; while the
/// app is open, messages come over the live connection instead.
class PushService {
  PushService._();
  static final instance = PushService._();

  Backend? _backend;
  String? _token;
  StreamSubscription? _refreshSub;
  StreamSubscription? _openSub;
  bool _firebaseReady = false;

  /// Opens a chat when a notification is tapped. Set by the app shell.
  void Function(String chatId)? onOpenChat;
  String? _pendingOpen;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) && OnlineConfig.pushConfigured;

  Future<bool> _initFirebase() async {
    if (_firebaseReady) return true;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: OnlineConfig.firebaseApiKey,
          appId: !kIsWeb && (Platform.isIOS || Platform.isMacOS) && OnlineConfig.firebaseIosAppId.isNotEmpty
              ? OnlineConfig.firebaseIosAppId
              : OnlineConfig.firebaseAppId,
          messagingSenderId: OnlineConfig.firebaseSenderId,
          projectId: OnlineConfig.firebaseProjectId,
        ),
      );
      _firebaseReady = true;
    } catch (e) {
      LogService().log('Push: Firebase setup failed: $e');
    }
    return _firebaseReady;
  }

  Future<void> start(Backend backend) async {
    _backend = backend;
    if (!supported || !await _initFirebase()) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      if (Platform.isAndroid) await _androidChannel();
      _token = await messaging.getToken();
      if (_token != null) await backend.registerDevice(_token!, Platform.operatingSystem);
      _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((t) async {
        _token = t;
        try {
          await _backend?.registerDevice(t, Platform.operatingSystem);
        } catch (_) {}
      });
      _openSub?.cancel();
      _openSub = FirebaseMessaging.onMessageOpenedApp.listen(_opened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _opened(initial);
    } catch (e) {
      LogService().log('Push: $e');
    }
  }

  /// The "Chats" notification channel (messages arrive in it).
  Future<void> _androidChannel() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'chat',
          'Chats',
          description: 'New messages in your chats',
          importance: Importance.high,
        ));
  }

  void _opened(RemoteMessage m) {
    final chatId = m.data['chat_id'];
    if (chatId is! String) return;
    final open = onOpenChat;
    if (open == null) {
      _pendingOpen = chatId;
    } else {
      open(chatId);
    }
  }

  /// A chat to open because a notification started the app.
  String? takePendingOpen() {
    final id = _pendingOpen;
    _pendingOpen = null;
    return id;
  }

  /// Signing out: this device stops getting this account's messages.
  Future<void> stop() async {
    final t = _token;
    final b = _backend;
    _refreshSub?.cancel();
    _openSub?.cancel();
    _token = null;
    _backend = null;
    if (t != null && b != null) {
      try {
        await b.unregisterDevice(t);
      } catch (_) {}
    }
  }
}
