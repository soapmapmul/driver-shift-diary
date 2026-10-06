import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

/// Мини-копия API для тестов клиента. Умеет «терять ответ»: запрос обработан,
/// поездка сохранена, а до клиента доходит обрыв связи.
class FakeServer {
  final trips = <String, Map<String, dynamic>>{};
  final posts = <Map<String, dynamic>>[];
  bool down = false;
  bool dropNextResponse = false;
  int? forceStatus;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    if (down) throw http.ClientException('Connection refused');
    final path = req.url.path;

    if (req.method == 'GET' && path == '/api/days') return _json(200, jsonDecode(daysJson));
    if (req.method == 'GET' && path == '/api/trips') {
      final date = req.url.queryParameters['date']!;
      final json = dayJsons[date];
      return _json(200, json != null ? jsonDecode(json) : _emptyDay(date));
    }
    if (req.method == 'POST' && path == '/api/trips') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      posts.add(body);
      if (forceStatus != null) {
        return _json(forceStatus!, {'error': {'code': 'forced', 'message': 'Ошибка $forceStatus'}});
      }
      final amount = body['amount'] as num?;
      if (amount == null || amount <= 0) {
        return _json(400, {
          'error': {
            'code': 'validation',
            'message': 'Некорректные данные поездки',
            'details': [{'field': 'amount', 'message': 'Сумма должна быть больше нуля'}],
          },
        });
      }
      final id = body['id'] as String;
      final created = !trips.containsKey(id);
      trips.putIfAbsent(id, () => body);
      final response = _json(created ? 201 : 200, {
        'created': created,
        'duplicate': !created,
        'trip': {
          ...trips[id]!,
          'date': (body['start'] as String).substring(0, 10),
          'durationMinutes': 20,
          'net': amount - (body['commission'] as num),
        },
      });
      if (dropNextResponse) {
        dropNextResponse = false;
        throw http.ClientException('Connection reset by peer');
      }
      return response;
    }
    return _json(404, {'error': {'code': 'not_found', 'message': 'Не найдено'}});
  }

  static http.Response _json(int status, Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static Map<String, dynamic> _emptyDay(String date) {
    const zero = {'trips': 0, 'revenue': 0, 'commission': 0, 'net': 0};
    return {
      'date': date,
      'utcOffset': '+05:00',
      'summary': {...zero, 'byPayment': {'cash': zero, 'card': zero}, 'serviceBalance': 0, 'driveMinutes': 0},
      'trips': <Object>[],
    };
  }
}
