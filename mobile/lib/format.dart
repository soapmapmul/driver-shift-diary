// Форматирование денег, дат и времени по-русски, без пакета intl.

const _nbsp = ' ';

const _months = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];
const _monthsShort = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];
const _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

/// Сумма в тиынах → «2 932,5 ₸». Знак ₸ не отрывается от числа.
String money(int minor) {
  final sign = minor < 0 ? '−' : '';
  final abs = minor.abs();
  final whole = (abs ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(_nbsp);
    buf.write(whole[i]);
  }
  final frac = abs % 100;
  final fracText = frac == 0
      ? ''
      : frac % 10 == 0
          ? ',${frac ~/ 10}'
          : ',${frac.toString().padLeft(2, '0')}';
  return '$sign$buf$fracText$_nbsp₸';
}

String duration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '$h ч ${m.toString().padLeft(2, '0')} мин' : '$m мин';
}

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

/// Дата «2026-10-01» → DateTime в UTC (полночь). Все «стенные» времена водителя
/// храним как UTC-значения, чтобы часовой пояс телефона ни на что не влиял.
DateTime parseDate(String date) =>
    DateTime.utc(int.parse(date.substring(0, 4)), int.parse(date.substring(5, 7)), int.parse(date.substring(8, 10)));

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String shiftDate(String date, int days) => dateKey(parseDate(date).add(Duration(days: days)));

String dayLabel(String date) {
  final d = parseDate(date);
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

String chipLabel(String date) {
  final d = parseDate(date);
  return '${d.day} ${_monthsShort[d.month - 1]}';
}

String hhmm(DateTime wall) => '${_two(wall.hour)}:${_two(wall.minute)}';

String dateTimeLabel(DateTime wall) => '${wall.day} ${_monthsShort[wall.month - 1]}, ${hhmm(wall)}';

/// «+05:00» → Duration.
Duration parseOffset(String offset) {
  if (offset == 'Z') return Duration.zero;
  final sign = offset.startsWith('-') ? -1 : 1;
  return Duration(
    minutes: sign * (int.parse(offset.substring(1, 3)) * 60 + int.parse(offset.substring(4, 6))),
  );
}

/// Время из API (ISO со смещением) → «стенные часы» водителя.
DateTime wallClock(String iso, String utcOffset) =>
    DateTime.parse(iso).toUtc().add(parseOffset(utcOffset));

/// «Стенные часы» водителя → ISO для API: 2026-10-01T08:10:00+05:00.
String toIso(DateTime wall, String utcOffset) =>
    '${dateKey(wall)}T${_two(wall.hour)}:${_two(wall.minute)}:00$utcOffset';

String todayIn(String utcOffset) => dateKey(DateTime.now().toUtc().add(parseOffset(utcOffset)));

String ago(Duration d) {
  if (d.inMinutes < 1) return 'только что';
  if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
  if (d.inHours < 24) return '${d.inHours} ч назад';
  return '${d.inDays} ${plural(d.inDays, 'день', 'дня', 'дней')} назад';
}

String _two(int v) => v.toString().padLeft(2, '0');
