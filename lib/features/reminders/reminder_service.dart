import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:intl/intl.dart';
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

  static const snoozeAction = 'snooze';
  static const snoozeFor = Duration(minutes: 10);

  /// Called when the person taps a reminder ([actionId] is null) or its
  /// Snooze button. Set by the home screen.
  void Function(String noteId, String? actionId)? onTap;

  /// A tap that started the app, waiting for the home screen.
  ({String noteId, String? actionId})? _launchTap;

  /// The tap that opened CodeNote from a closed state, once.
  ({String noteId, String? actionId})? takeLaunchTap() {
    final t = _launchTap;
    _launchTap = null;
    return t;
  }

  /// How a reminder looks: CodeNote's violet, the full message when it's
  /// pulled down, the time, and Snooze / Open buttons.
  static NotificationDetails _details(String title, String body, DateTime when) {
    final time = DateFormat.jm().format(when);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'codenote_reminders',
        'Reminders',
        channelDescription: 'Reminders you set on notes',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        color: const Color(0xFF7B5CFF),
        subText: 'Reminder · $time',
        ticker: title,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Reminder · $time',
        ),
        actions: const [
          AndroidNotificationAction(snoozeAction, 'Snooze 10 min', showsUserInterface: true),
          AndroidNotificationAction('open', 'Open note', showsUserInterface: true),
        ],
      ),
      iOS: DarwinNotificationDetails(subtitle: 'Reminder · $time', threadIdentifier: 'reminders'),
      macOS: DarwinNotificationDetails(subtitle: 'Reminder · $time', threadIdentifier: 'reminders'),
    );
  }

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
        onDidReceiveNotificationResponse: _tapped,
      );
      _ready = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final r = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && r?.payload != null) {
        _launchTap = (noteId: r!.payload!, actionId: r.actionId);
      }
    } catch (e) {
      LogService().log('Reminders: setup failed: $e');
    }
  }

  void _tapped(NotificationResponse r) {
    final id = r.payload;
    if (id == null) return;
    final handler = onTap;
    if (handler == null) {
      _launchTap = (noteId: id, actionId: r.actionId);
    } else {
      handler(id, r.actionId);
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
      final title = note.title.trim().isEmpty ? 'Reminder' : note.title.trim();
      final body = reminder.message.trim().isEmpty ? 'Tap to open the note' : reminder.message.trim();
      await _plugin.zonedSchedule(
        id: id,
        // An exact instant, so the device's time zone is handled for us.
        scheduledDate: tz.TZDateTime.from(reminder.dateTime, tz.UTC),
        notificationDetails: _details(title, body, reminder.dateTime),
        // Inexact needs no special permission; it fires within a minute or two.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
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
