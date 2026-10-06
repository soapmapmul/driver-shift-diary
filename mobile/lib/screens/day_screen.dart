import 'package:flutter/material.dart';

import '../api.dart';
import '../controller.dart';
import '../format.dart';
import '../models.dart';
import '../widgets.dart';
import 'add_trip_sheet.dart';

class DayScreen extends StatelessWidget {
  const DayScreen({super.key, required this.controller});

  final DiaryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Дневник смен'),
            actions: [
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh),
                onPressed: c.loading ? null : c.refresh,
              ),
              IconButton(
                tooltip: 'Сервер',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _editServer(context),
              ),
            ],
          ),
          floatingActionButton: c.date.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => showAddTripSheet(context, c),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
          body: c.date.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: c.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    children: [
                      _DateNav(controller: c),
                      _DayChips(controller: c),
                      _Status(controller: c),
                      if (c.pending != null) _PendingBanner(controller: c),
                      ..._content(context, c),
                    ],
                  ),
                ),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, DiaryController c) {
    final day = c.day;
    if (day == null) return const [];
    final title = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return [
      SummaryCard(summary: day.summary),
      const SizedBox(height: 24),
      Text('Смена по часам', style: title),
      const SizedBox(height: 8),
      Timeline(day: day),
      const SizedBox(height: 24),
      Text('Поездки', style: title),
      const SizedBox(height: 8),
      if (day.trips.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('В этот день поездок нет.', style: TextStyle(color: Theme.of(context).hintColor))),
        ),
      for (final t in day.trips)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TripTile(trip: t, utcOffset: day.utcOffset, highlight: t.id == c.highlightId),
        ),
    ];
  }

  Future<void> _editServer(BuildContext context) async {
    final field = TextEditingController(text: controller.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Адрес сервера'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: field,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'http://192.168.1.10:3000'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Эмулятор Android: http://10.0.2.2:3000\n'
              'Телефон: IP компьютера в той же Wi-Fi сети, порт 3000',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    field.dispose();
    if (url != null && url.isNotEmpty) await controller.setBaseUrl(url);
  }
}

class _DateNav extends StatelessWidget {
  const _DateNav({required this.controller});

  final DiaryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Row(children: [
      IconButton.outlined(
        tooltip: 'Предыдущий день',
        onPressed: () => c.shift(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: parseDate(c.date),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) await c.open(dateKey(picked));
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: Text(dayLabel(c.date), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.outlined(
        tooltip: 'Следующий день',
        onPressed: () => c.shift(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ]);
  }
}

class _DayChips extends StatelessWidget {
  const _DayChips({required this.controller});

  final DiaryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.days.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final DayCount d in c.days)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${chipLabel(d.date)} · ${d.trips}'),
                tooltip: '${dayLabel(d.date)}: ${d.trips} ${plural(d.trips, 'поездка', 'поездки', 'поездок')}',
                selected: d.date == c.date,
                showCheckmark: false,
                onSelected: (_) => c.open(d.date),
              ),
            ),
        ],
      ),
    );
  }
}

/// Загрузка, ошибка или «обновлено N мин назад», если на экране данные из кэша.
class _Status extends StatelessWidget {
  const _Status({required this.controller});

  final DiaryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    if (c.error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(children: [
              Expanded(
                child: Text(
                  c.day != null && c.updatedAt != null
                      ? '${c.error}. Показаны сохранённые данные, обновлены ${ago(DateTime.now().difference(c.updatedAt!))}.'
                      : '${c.error}. Адрес сервера: ${c.baseUrl}',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
              TextButton(onPressed: c.refresh, child: const Text('Повторить')),
            ]),
          ),
        ),
      );
    }
    if (c.loading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(
            c.updatedAt != null
                ? 'Обновляю… На экране данные от ${ago(DateTime.now().difference(c.updatedAt!))}'
                : 'Загружаю…',
            style: small,
          ),
        ]),
      );
    }
    return const SizedBox(height: 4);
  }
}

/// Поездка ушла на сервер, но подтверждения нет. Повтор отправит её с тем же id — дубля не будет.
class _PendingBanner extends StatefulWidget {
  const _PendingBanner({required this.controller});

  final DiaryController controller;

  @override
  State<_PendingBanner> createState() => _PendingBannerState();
}

class _PendingBannerState extends State<_PendingBanner> {
  bool _sending = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.controller.resendPending();
      if (result != null) {
        messenger.showSnackBar(SnackBar(
          content: Text(result.created ? 'Поездка сохранена' : 'Поездка уже была на сервере, дубль не создан'),
        ));
      }
    } on NetworkException {
      messenger.showSnackBar(const SnackBar(content: Text('Связи всё ещё нет, попробуйте позже')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.pending!;
    final offset = widget.controller.utcOffset;
    final theme = Theme.of(context);
    String describe() {
      try {
        final start = wallClock(p['start'] as String, offset);
        final end = wallClock(p['end'] as String, offset);
        return '${dateTimeLabel(start)}–${hhmm(end)}, ${money(toMinor(p['amount']))}';
      } catch (_) {
        return 'поездка';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Сервер не подтвердил поездку ${describe()}. '
                'Повторная отправка не создаст дубль.',
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: _sending ? null : widget.controller.discardPending,
                  child: const Text('Забыть'),
                ),
                FilledButton.tonal(
                  onPressed: _sending ? null : _resend,
                  child: Text(_sending ? 'Отправляю…' : 'Отправить ещё раз'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
