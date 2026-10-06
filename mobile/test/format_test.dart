import 'dart:convert';

import 'package:driver_shift_diary/format.dart';
import 'package:driver_shift_diary/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const nb = ' ';

void main() {
  test('деньги: разряды, копейки, минус, знак ₸ не отрывается', () {
    expect(money(240000), '2${nb}400$nb₸');
    expect(money(293250), '2${nb}932,5$nb₸');
    expect(money(1), '0,01$nb₸');
    expect(money(100000000), '1${nb}000${nb}000$nb₸');
    expect(money(-30000), '−300$nb₸');
  });

  test('тиыны: 0.1 + 0.2 без ошибок плавающей точки', () {
    expect(toMinor(0.1) + toMinor(0.2), 30);
    expect(toMinor(2932.5), 293250);
  });

  test('даты и время водителя не зависят от пояса телефона', () {
    expect(dayLabel('2026-10-01'), 'чт, 1 октября');
    expect(shiftDate('2026-10-31', 1), '2026-11-01');
    expect(shiftDate('2026-03-01', -1), '2026-02-28');

    final wall = wallClock('2026-09-30T20:30:00Z', '+05:00');
    expect(dateKey(wall), '2026-10-01');
    expect(hhmm(wall), '01:30');
    expect(toIso(DateTime.utc(2026, 10, 1, 8, 10), '+05:00'), '2026-10-01T08:10:00+05:00');
  });

  test('длительность и склонения', () {
    expect(duration(213), '3 ч 33 мин');
    expect(duration(22), '22 мин');
    expect(plural(1, 'поездка', 'поездки', 'поездок'), 'поездка');
    expect(plural(3, 'поездка', 'поездки', 'поездок'), 'поездки');
    expect(plural(11, 'поездка', 'поездки', 'поездок'), 'поездок');
  });

  test('разбор ответа сервера за 1 октября', () {
    final day = DayData.fromJson(jsonDecode(dayJsons['2026-10-01']!) as Map<String, dynamic>);
    expect(day.trips, hasLength(8));
    expect(day.summary.total.net, 1661750);
    expect(day.summary.cash.revenue, 705000);
    expect(day.summary.card.commission, 187500);
    expect(day.summary.serviceBalance, 956750);
    expect(day.trips.last.id, 't8');
  });
}
