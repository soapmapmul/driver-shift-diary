// Модели ответа API. Деньги внутри приложения — целые тиыны.

int toMinor(Object? value) => ((value as num) * 100).round();

class Trip {
  const Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
    required this.date,
    required this.durationMinutes,
    required this.net,
  });

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        start: j['start'] as String,
        end: j['end'] as String,
        amount: toMinor(j['amount']),
        payment: j['payment'] as String,
        commission: toMinor(j['commission']),
        date: j['date'] as String,
        durationMinutes: j['durationMinutes'] as int,
        net: toMinor(j['net']),
      );

  final String id;
  final String start;
  final String end;
  final int amount;
  final String payment;
  final int commission;
  final String date;
  final int durationMinutes;
  final int net;

  bool get isCash => payment == 'cash';
}

class PaymentSummary {
  const PaymentSummary({required this.trips, required this.revenue, required this.commission, required this.net});

  factory PaymentSummary.fromJson(Map<String, dynamic> j) => PaymentSummary(
        trips: j['trips'] as int,
        revenue: toMinor(j['revenue']),
        commission: toMinor(j['commission']),
        net: toMinor(j['net']),
      );

  final int trips;
  final int revenue;
  final int commission;
  final int net;
}

class Summary {
  const Summary({
    required this.total,
    required this.cash,
    required this.card,
    required this.serviceBalance,
    required this.driveMinutes,
  });

  factory Summary.fromJson(Map<String, dynamic> j) {
    final byPayment = j['byPayment'] as Map<String, dynamic>;
    return Summary(
      total: PaymentSummary.fromJson(j),
      cash: PaymentSummary.fromJson(byPayment['cash'] as Map<String, dynamic>),
      card: PaymentSummary.fromJson(byPayment['card'] as Map<String, dynamic>),
      serviceBalance: toMinor(j['serviceBalance']),
      driveMinutes: j['driveMinutes'] as int,
    );
  }

  final PaymentSummary total;
  final PaymentSummary cash;
  final PaymentSummary card;

  /// Расчёт с сервисом: карта минус вся комиссия. Меньше нуля — водитель должен сервису.
  final int serviceBalance;
  final int driveMinutes;
}

class DayData {
  const DayData({required this.date, required this.utcOffset, required this.summary, required this.trips});

  factory DayData.fromJson(Map<String, dynamic> j) => DayData(
        date: j['date'] as String,
        utcOffset: j['utcOffset'] as String,
        summary: Summary.fromJson(j['summary'] as Map<String, dynamic>),
        trips: [for (final t in j['trips'] as List) Trip.fromJson(t as Map<String, dynamic>)],
      );

  final String date;
  final String utcOffset;
  final Summary summary;
  final List<Trip> trips;
}

class DayCount {
  const DayCount(this.date, this.trips);
  final String date;
  final int trips;
}

class DaysList {
  const DaysList(this.utcOffset, this.days);

  factory DaysList.fromJson(Map<String, dynamic> j) => DaysList(
        j['utcOffset'] as String,
        [
          for (final d in j['days'] as List)
            DayCount((d as Map<String, dynamic>)['date'] as String, d['trips'] as int),
        ],
      );

  final String utcOffset;
  final List<DayCount> days;
}

class FieldError {
  const FieldError(this.field, this.message);

  factory FieldError.fromJson(Map<String, dynamic> j) => FieldError(j['field'] as String?, j['message'] as String);

  final String? field;
  final String message;
}

class AddResult {
  const AddResult({required this.created, required this.trip});
  final bool created;
  final Trip trip;
}
