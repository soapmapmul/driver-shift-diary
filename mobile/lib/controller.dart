import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';

/// Адрес сервера по умолчанию. Эмулятор Android видит компьютер как 10.0.2.2.
/// Для телефона адрес задаётся в настройках приложения или через --dart-define=API_URL=...
String get defaultApiUrl {
  const fromEnv = String.fromEnvironment('API_URL');
  if (fromEnv.isNotEmpty) return fromEnv;
  return kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';
}

/// Ключ идемпотентности: случайные 128 бит.
String newTripId() {
  final rnd = Random.secure();
  return 'm-${List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

class DiaryController extends ChangeNotifier {
  DiaryController({required this.prefs, http.Client? httpClient}) : _httpClient = httpClient ?? http.Client() {
    _api = DiaryApi(baseUrl, client: _httpClient);
  }

  static const _urlKey = 'api_url';
  static const _daysKey = 'days';
  static const _pendingKey = 'pending_trip';

  final SharedPreferences prefs;
  final http.Client _httpClient;
  late DiaryApi _api;

  String utcOffset = '+05:00';
  List<DayCount> days = const [];
  String date = '';
  DayData? day;

  /// Когда данные дня последний раз пришли с сервера (для кэша — когда были сохранены).
  DateTime? updatedAt;
  bool loading = false;
  String? error;
  String? highlightId;
  int _seq = 0;

  String get baseUrl => prefs.getString(_urlKey) ?? defaultApiUrl;

  Future<void> setBaseUrl(String url) async {
    await prefs.setString(_urlKey, url);
    _api = DiaryApi(url, client: _httpClient);
    await start();
  }

  Future<void> start() async {
    await _loadDays();
    await open(days.isNotEmpty ? days.last.date : todayIn(utcOffset));
  }

  Future<void> _loadDays() async {
    try {
      final json = await _api.getDaysJson();
      await prefs.setString(_daysKey, jsonEncode(json));
      _applyDays(json);
    } on Exception {
      final cached = prefs.getString(_daysKey);
      if (cached != null) _applyDays(jsonDecode(cached) as Map<String, dynamic>);
    }
  }

  void _applyDays(Map<String, dynamic> json) {
    final list = DaysList.fromJson(json);
    utcOffset = list.utcOffset;
    days = list.days;
  }

  /// Показывает день сразу из кэша, если он есть, и параллельно запрашивает свежие данные.
  Future<void> open(String newDate) async {
    final seq = ++_seq;
    date = newDate;
    error = null;
    day = null;
    updatedAt = null;
    final cached = prefs.getString('day:$newDate');
    if (cached != null) {
      final entry = jsonDecode(cached) as Map<String, dynamic>;
      day = DayData.fromJson(entry['body'] as Map<String, dynamic>);
      updatedAt = DateTime.parse(entry['at'] as String);
    }
    loading = true;
    notifyListeners();

    try {
      final json = await _api.getDayJson(newDate);
      if (seq != _seq) return; // пока грузили, водитель переключил день
      day = DayData.fromJson(json);
      utcOffset = day!.utcOffset;
      updatedAt = DateTime.now();
      await prefs.setString('day:$newDate', jsonEncode({'at': updatedAt!.toIso8601String(), 'body': json}));
    } on Exception catch (e) {
      if (seq != _seq) return;
      error = e.toString();
    } finally {
      if (seq == _seq) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    await _loadDays();
    await open(date);
  }

  Future<void> shift(int delta) => open(shiftDate(date, delta));

  // ---------- добавление поездки ----------

  /// Поездка, отправленная на сервер, но без подтверждения (обрыв связи, приложение закрыли).
  Map<String, dynamic>? get pending {
    final raw = prefs.getString(_pendingKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Отправляет поездку. До запроса сохраняет её вместе с ключом `id` на телефоне:
  /// если ответ потеряется, повтор (даже после перезапуска) уйдёт с тем же id,
  /// и сервер вернёт уже созданную поездку вместо дубля.
  Future<AddResult> addTrip(Map<String, dynamic> payload) async {
    assert(payload['id'] is String, 'payload must carry an idempotency id');
    await prefs.setString(_pendingKey, jsonEncode(payload));
    notifyListeners();

    final AddResult result;
    try {
      result = await _api.addTrip(payload);
    } on ApiException catch (e) {
      // 4xx — сервер точно ничего не создал, повторять нечего. 5xx — неизвестно, оставляем.
      if (e.status < 500) await _clearPending();
      rethrow;
    }

    await _clearPending();
    highlightId = result.trip.id;
    await _loadDays();
    await open(result.trip.date);
    return result;
  }

  Future<AddResult?> resendPending() async {
    final payload = pending;
    return payload == null ? null : addTrip(payload);
  }

  Future<void> discardPending() => _clearPending();

  Future<void> _clearPending() async {
    await prefs.remove(_pendingKey);
    notifyListeners();
  }

  /// Время начала для новой поездки: свободные 20 минут внутри дня. Сначала после
  /// самой поздней поездки, затем после более ранних, затем 09:00 и 00:00.
  DateTime suggestStart() {
    const slot = Duration(minutes: 20);
    const gap = Duration(minutes: 5);
    final dayStart = parseDate(date);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final busy = [
      for (final t in day?.trips ?? const <Trip>[])
        (wallClock(t.start, utcOffset), wallClock(t.end, utcOffset)),
    ];
    bool fits(DateTime from) {
      final to = from.add(slot);
      return !from.isBefore(dayStart) &&
          !to.isAfter(dayEnd) &&
          busy.every((b) => !to.isAfter(b.$1) || !from.isBefore(b.$2));
    }

    final nine = dayStart.add(const Duration(hours: 9));
    final candidates = [...busy.reversed.map((b) => b.$2.add(gap)), nine, dayStart];
    return candidates.firstWhere(fits, orElse: () => nine);
  }
}
