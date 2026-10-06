import 'dart:math';

import 'package:flutter/material.dart';

import 'format.dart';
import 'main.dart' show cardColor, cashColor;
import 'models.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = s.total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('НА РУКИ', style: theme.textTheme.labelMedium?.copyWith(color: muted, letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(
              money(total.net),
              key: const Key('net'),
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              total.trips > 0
                  ? 'выручка ${money(total.revenue)} минус комиссия ${money(total.commission)}'
                  : 'поездок нет',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            Row(children: [
              _Stat('Поездок', '${total.trips}'),
              const SizedBox(width: 8),
              _Stat('Выручка', money(total.revenue)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _Stat('Комиссия', money(total.commission)),
              const SizedBox(width: 8),
              _Stat('В пути', duration(s.driveMinutes)),
            ]),
            const SizedBox(height: 16),
            _SplitBar(cash: s.cash.revenue, card: s.card.revenue),
            const SizedBox(height: 10),
            Wrap(spacing: 20, runSpacing: 4, children: [
              _Legend(color: cashColor, label: 'Наличные', value: money(s.cash.revenue), count: s.cash.trips),
              _Legend(color: cardColor, label: 'Карта', value: money(s.card.revenue), count: s.card.trips),
            ]),
            if (total.trips > 0) ...[
              const SizedBox(height: 10),
              Text(
                s.serviceBalance >= 0
                    ? 'Наличные ${money(s.cash.revenue)} уже у вас, сервис доплатит ${money(s.serviceBalance)} '
                        '(карта минус вся комиссия).'
                    : 'Наличные ${money(s.cash.revenue)} у вас, сервису нужно вернуть '
                        '${money(-s.serviceBalance)} комиссии.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.cash, required this.card});

  final int cash;
  final int card;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      // ColoredBox без child берёт минимальный размер: высоту и ширину задаём явно,
      // а Row растягивает отрезки по высоте (stretch), иначе полоса схлопывается в 0.
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: cash + card == 0
            ? ColoredBox(color: Theme.of(context).colorScheme.outlineVariant)
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (cash > 0) Expanded(flex: cash, child: const ColoredBox(key: Key('split-cash'), color: cashColor)),
                if (card > 0) Expanded(flex: card, child: const ColoredBox(key: Key('split-card'), color: cardColor)),
              ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value, required this.count});

  final Color color;
  final String label;
  final String value;
  final int count;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text.rich(TextSpan(children: [
        TextSpan(text: '$label '),
        TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (count > 0) TextSpan(text: ' $count шт.', style: TextStyle(color: muted, fontSize: 12)),
      ])),
    ]);
  }
}

/// Шкала смены: 24 часа, поездки — цветные отрезки. Ночная поездка обрезается полуночью.
class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.day});

  final DayData day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      SizedBox(
        height: 28,
        width: double.infinity,
        child: CustomPaint(
          painter: _TimelinePainter(
            day: day,
            background: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            grid: scheme.outlineVariant,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final h in const [0, 6, 12, 18, 24])
            Text('$h', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    ]);
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.day, required this.background, required this.grid});

  final DayData day;
  final Color background;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = background,
    );
    final gridPaint = Paint()..color = grid;
    for (var h = 1; h < 24; h++) {
      final x = size.width * h / 24;
      canvas.drawRect(Rect.fromLTWH(x, 0, h % 6 == 0 ? 1.5 : 0.5, size.height), gridPaint);
    }
    final dayStart = parseDate(day.date);
    double x(DateTime t) => size.width * t.difference(dayStart).inMinutes.clamp(0, 1440) / 1440;
    for (final t in day.trips) {
      final from = x(wallClock(t.start, day.utcOffset));
      final to = max(from + 3, x(wallClock(t.end, day.utcOffset)));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(from, 4, to, size.height - 4), const Radius.circular(3)),
        Paint()..color = t.isCash ? cashColor : cardColor,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.day != day || old.background != background;
}

class TripTile extends StatelessWidget {
  const TripTile({super.key, required this.trip, required this.utcOffset, this.highlight = false});

  final Trip trip;
  final String utcOffset;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final start = wallClock(trip.start, utcOffset);
    final end = wallClock(trip.end, utcOffset);
    final nextDay = dateKey(end) != trip.date ? ' (+1 день)' : '';
    final color = trip.isCash ? cashColor : cardColor;

    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${hhmm(start)}–${hhmm(end)}$nextDay',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(trip.isCash ? 'Наличные' : 'Карта',
                            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Text('${duration(trip.durationMinutes)} · комиссия ${money(trip.commission)}', style: muted),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(trip.amount), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('на руки ${money(trip.net)}', style: muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
