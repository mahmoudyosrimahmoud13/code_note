import 'package:code_note/features/reminders/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reminder ids are stable, positive and 32-bit', () {
    final a = ReminderService.idFor('note-abc');
    expect(a, ReminderService.idFor('note-abc'));
    expect(a, greaterThan(0));
    expect(a, lessThanOrEqualTo(0x7fffffff));
    expect(ReminderService.idFor('note-abd'), isNot(a));
  });
}
