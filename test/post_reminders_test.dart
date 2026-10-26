import 'package:flutter_test/flutter_test.dart';
import 'package:luli_for_reddit/features/reminders/post_reminders.dart';

void main() {
  group('whenLabel', () {
    // A Monday afternoon.
    final now = DateTime(2026, 10, 26, 14, 0);

    test('today and tomorrow', () {
      expect(whenLabel(DateTime(2026, 10, 26, 15, 0), now, use24h: true),
          'today at 15:00');
      expect(whenLabel(DateTime(2026, 10, 27, 9, 0), now, use24h: true),
          'tomorrow at 09:00');
    });

    test('a weekday within the week, then the date', () {
      expect(whenLabel(DateTime(2026, 10, 29, 18, 5), now, use24h: true),
          'Thu at 18:05');
      expect(whenLabel(DateTime(2026, 11, 2, 10, 0), now, use24h: true),
          'on Nov 2 at 10:00');
    });

    test('12-hour clock', () {
      expect(whenLabel(DateTime(2026, 10, 26, 15, 0), now, use24h: false),
          'today at 3:00\u202fPM'); // intl's narrow no-break space
    });

    test('past due', () {
      expect(whenLabel(now, now, use24h: true), 'any moment now');
    });
  });

  test('pending reminders read back, junk ignored', () {
    expect(decodeReminders('{"abc":1761490800000,"x":"y"}'),
        {'abc': 1761490800000});
    expect(decodeReminders('not json'), isEmpty);
    expect(decodeReminders(null), isEmpty);
  });

  test('notification id matches Kotlin ("reminder_<id>".hashCode())', () {
    expect(reminderNotificationId('1abcde'), 2024383295);
  });
}
