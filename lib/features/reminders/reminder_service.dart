import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/services/log_service.dart';
import '../notes/domain/entities/note.dart';

/// Real reminder alerts.
///
/// Android, iOS and macOS: a system notification is scheduled, so it
/// arrives even when CodeNote is closed. Windows and Linux: the home screen
/// checks every 30 seconds and shows an in-app pop-up ([dueReminders]).
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get systemNotifications =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static const _channel = AndroidNotificationDetails(
    'codenote_reminders',
    'Reminders',
    channelDescription: 'Reminders you set on notes',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// A stable number for a note id (notification ids must be ints, and
  /// String.hashCode can change between app runs).
  static int idFor(String noteId) {
    var hash = 0x811c9dc5;
    for (final unit in noteId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> init() async {
    if (_ready || !systemNotifications) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_light'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
    } catch (e) {
      LogService().log('Reminders: setup failed: $e');
    }
  }

  /// Asks for permission to show notifications (Android 13+, iOS, macOS).
  /// Called the first time someone sets a reminder.
  Future<void> requestPermission() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Schedules or cancels the alert for [note] to match its reminder.
  Future<void> sync(NoteEntity note) async {
    if (!systemNotifications) return;
    await init();
    if (!_ready) return;
    final id = idFor(note.id);
    try {
      await _plugin.cancel(id: id);
      final reminder = note.reminder;
      if (reminder == null ||
          note.isTrashed ||
          reminder.dateTime.isBefore(DateTime.now())) {
        return;
      }
      await _plugin.zonedSchedule(
        id: id,
        // An exact instant, so the device's time zone is handled for us.
        scheduledDate: tz.TZDateTime.from(reminder.dateTime, tz.UTC),
        notificationDetails: _details,
        // Inexact needs no special permission; it fires within a minute or two.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: note.title.trim().isEmpty ? 'Reminder' : note.title.trim(),
        body: reminder.message.trim().isEmpty ? 'Open CodeNote' : reminder.message.trim(),
        payload: note.id,
      );
    } catch (e) {
      LogService().log('Reminders: could not schedule ${note.id}: $e');
    }
  }

  Future<void> cancel(String noteId) async {
    if (!systemNotifications || !_ready) return;
    try {
      await _plugin.cancel(id: idFor(noteId));
    } catch (_) {}
  }

  /// Re-schedules every future reminder (at startup).
  Future<void> syncAll(List<NoteEntity> notes) async {
    for (final note in notes.where((n) => n.reminder != null)) {
      await sync(note);
    }
  }

  // ─── Windows and Linux: in-app pop-ups ──────────────────

  static const _boxName = 'appBox';
  static const _firedKey = 'FIRED_REMINDERS';

  /// Reminders whose time has come and that haven't been shown yet.
  /// Marks them as shown.
  Future<List<NoteEntity>> dueReminders(List<NoteEntity> notes) async {
    final box = Hive.isBoxOpen(_boxName)
        ? Hive.box(_boxName)
        : await Hive.openBox(_boxName);
    final fired = Set<String>.from(
        (box.get(_firedKey) as List?)?.cast<String>() ?? const []);
    final now = DateTime.now();
    final due = <NoteEntity>[];
    for (final note in notes) {
      final r = note.reminder;
      if (r == null || note.isTrashed || r.dateTime.isAfter(now)) continue;
      // Only remind about things from the last day, not ancient ones.
      if (now.difference(r.dateTime) > const Duration(days: 1)) continue;
      final key = '${note.id}@${r.dateTime.toIso8601String()}';
      if (fired.add(key)) due.add(note);
    }
    if (due.isNotEmpty) {
      final keep = fired.toList();
      await box.put(_firedKey, keep.length > 300 ? keep.sublist(keep.length - 300) : keep);
    }
    return due;
  }
}
