import 'package:driver_shift_diary/api.dart';
import 'package:driver_shift_diary/controller.dart';
import 'package:driver_shift_diary/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

Map<String, dynamic> trip(String id, {num amount = 1700}) => {
      'id': id,
      'start': '2026-10-05T10:00:00+05:00',
      'end': '2026-10-05T10:20:00+05:00',
      'amount': amount,
      'payment': 'cash',
      'commission': 255,
    };

void main() {
  late FakeServer server;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    server = FakeServer();
  });

  DiaryController make() => DiaryController(prefs: prefs, httpClient: server.client);

  group('вывод из «ответ потерялся» без дублей', () {
    test('поездка сохраняется на телефоне до отправки, повтор идёт с тем же id', () async {
      final c = make();
      await c.start();

      server.dropNextResponse = true; // сервер сохранил, но ответ не дошёл
      await expectLater(c.addTrip(trip('m-1')), throwsA(isA<NetworkException>()));
      expect(server.trips, hasLength(1));
      expect(c.pending?['id'], 'm-1');

      final result = await c.resendPending();
      expect(result!.created, isFalse); // сервер узнал поездку
      expect(server.posts.map((p) => p['id']), ['m-1', 'm-1']);
      expect(server.trips, hasLength(1));
      expect(c.pending, isNull);
    });

    test('неподтверждённая поездка переживает перезапуск приложения', () async {
      server.down = true;
      await expectLater(make().addTrip(trip('m-2')), throwsA(isA<NetworkException>()));

      server.down = false;
      final restarted = make(); // новый контроллер на тех же SharedPreferences
      expect(restarted.pending?['id'], 'm-2');
      expect((await restarted.resendPending())!.created, isTrue);
      expect(restarted.pending, isNull);
    });

    test('ошибка 4xx — ответ окончательный, повторять нечего', () async {
      final c = make();
      await expectLater(c.addTrip(trip('m-3', amount: 0)), throwsA(isA<ApiException>()));
      expect(c.pending, isNull);
    });

    test('ошибка 5xx — результат неизвестен, поездка остаётся к повтору', () async {
      final c = make();
      server.forceStatus = 503;
      await expectLater(c.addTrip(trip('m-4')), throwsA(isA<ApiException>()));
      expect(c.pending?['id'], 'm-4');
    });
  });

  test('без связи день показывается из кэша с отметкой ошибки', () async {
    final c = make();
    await c.start(); // открывается последний день с поездками
    expect(c.date, '2026-10-02');
    expect(c.error, isNull);

    server.down = true;
    final offline = make();
    await offline.start();
    expect(offline.date, '2026-10-02'); // список дней тоже из кэша
    expect(offline.day?.summary.total.trips, 5);
    expect(offline.error, isNotNull);
    expect(offline.updatedAt, isNotNull);
  });

  group('подсказка времени новой поездки', () {
    test('не уходит на следующий день после ночной поездки', () async {
      final c = make();
      await c.open('2026-10-01'); // последняя поездка 23:40–00:05
      final start = c.suggestStart();
      expect(dateKey(start), '2026-10-01');
      expect(hhmm(start), '19:33'); // после поездки, закончившейся в 19:28
    });

    test('в пустой день — 09:00', () async {
      final c = make();
      await c.open('2026-10-05');
      expect(hhmm(c.suggestStart()), '09:00');
    });
  });

  test('ключи идемпотентности уникальны', () {
    final ids = {for (var i = 0; i < 1000; i++) newTripId()};
    expect(ids, hasLength(1000));
  });
}
