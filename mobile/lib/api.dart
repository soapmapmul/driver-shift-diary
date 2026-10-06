import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Сервер ответил ошибкой (4xx/5xx) — ответ определённый.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details = const []]);

  final int status;
  final String code;
  final String message;
  final List<FieldError> details;

  @override
  String toString() => message;
}

/// Ответа нет: обрыв связи или таймаут. Запрос мог дойти до сервера, а мог и нет.
class NetworkException implements Exception {
  NetworkException(this.cause);

  final Object cause;

  @override
  String toString() => 'Нет связи с сервером';
}

class DiaryApi {
  DiaryApi(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse(baseUrl).resolve(path);
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } catch (e) {
      throw NetworkException(e);
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(res.statusCode, 'bad_response', 'Сервер вернул неожиданный ответ (${res.statusCode})');
    }
    if (res.statusCode >= 400) {
      final error = body['error'] as Map<String, dynamic>? ?? const {};
      throw ApiException(
        res.statusCode,
        error['code'] as String? ?? 'error',
        error['message'] as String? ?? 'Ошибка сервера (${res.statusCode})',
        [for (final d in error['details'] as List? ?? const []) FieldError.fromJson(d as Map<String, dynamic>)],
      );
    }
    return body;
  }

  /// Сырой JSON дня: его же кладём в кэш.
  Future<Map<String, dynamic>> getDayJson(String date) =>
      _send(() => _client.get(_uri('/api/trips', {'date': date})));

  Future<Map<String, dynamic>> getDaysJson() => _send(() => _client.get(_uri('/api/days')));

  /// [payload] уже содержит `id` — ключ идемпотентности: повтор с тем же id не создаст дубль.
  Future<AddResult> addTrip(Map<String, dynamic> payload) async {
    final body = await _send(() => _client.post(
          _uri('/api/trips'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ));
    return AddResult(
      created: body['created'] as bool,
      trip: Trip.fromJson(body['trip'] as Map<String, dynamic>),
    );
  }
}
