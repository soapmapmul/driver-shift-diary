import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../controller.dart';
import '../format.dart';
import '../models.dart';

Future<void> showAddTripSheet(BuildContext context, DiaryController controller) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showModalBottomSheet<AddResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AddTripSheet(controller: controller),
  );
  if (result != null) {
    messenger.showSnackBar(SnackBar(
      content: Text(result.created ? 'Поездка добавлена' : 'Такая поездка уже есть, дубль не создан'),
    ));
  }
}

class AddTripSheet extends StatefulWidget {
  const AddTripSheet({super.key, required this.controller});

  final DiaryController controller;

  @override
  State<AddTripSheet> createState() => _AddTripSheetState();
}

class _AddTripSheetState extends State<AddTripSheet> {
  // Ключ идемпотентности живёт, пока открыта форма: повторное «Сохранить»
  // после обрыва связи уйдёт с тем же id.
  final String _id = newTripId();
  final _amount = TextEditingController();
  final _commission = TextEditingController();
  late DateTime _start;
  late DateTime _end;
  String _payment = 'card';
  bool _commissionTouched = false;
  bool _sending = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.controller.suggestStart();
    _end = _start.add(const Duration(minutes: 20));
    _amount.addListener(_autoCommission);
  }

  @override
  void dispose() {
    _amount.dispose();
    _commission.dispose();
    super.dispose();
  }

  static num? _parse(String text) {
    final clean = text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    if (clean.isEmpty) return null;
    final value = double.tryParse(clean);
    if (value == null) return double.nan;
    return value == value.roundToDouble() ? value.toInt() : value;
  }

  void _autoCommission() {
    if (_commissionTouched) return;
    final amount = _parse(_amount.text);
    _commission.text = amount != null && !amount.isNaN && amount > 0
        ? (toMinor(amount) * 15 / 10000).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '').replaceAll('.', ',')
        : '';
  }

  Future<void> _pick({required bool start}) async {
    final current = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null) return;
    final picked = DateTime.utc(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (start) {
        final length = _end.isAfter(_start) ? _end.difference(_start) : const Duration(minutes: 20);
        _start = picked;
        _end = picked.add(length);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    final amount = _parse(_amount.text);
    final commission = _parse(_commission.text);
    final local = <String, String>{
      if (amount != null && amount.isNaN) 'amount': 'Введите число',
      if (commission != null && commission.isNaN) 'commission': 'Введите число',
    };
    if (local.isNotEmpty) return setState(() => _fieldErrors = local);

    setState(() {
      _sending = true;
      _fieldErrors = const {};
      _error = null;
    });
    final offset = widget.controller.utcOffset;
    try {
      final result = await widget.controller.addTrip({
        'id': _id,
        'start': toIso(_start, offset),
        'end': toIso(_end, offset),
        'amount': amount,
        'payment': _payment,
        'commission': commission,
      });
      if (mounted) Navigator.pop(context, result);
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = {for (final d in e.details) if (d.field != null) d.field!: d.message};
        final general = e.details.where((d) => d.field == null).map((d) => d.message);
        _error = e.details.isEmpty ? e.message : (general.isEmpty ? null : general.join('\n'));
      });
    } on NetworkException {
      setState(() => _error = 'Нет связи с сервером. Нажмите «Сохранить» ещё раз, дубля не будет.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]'))];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Новая поездка', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _TimeField(label: 'Начало', value: _start, error: _fieldErrors['start'], onTap: () => _pick(start: true))),
              const SizedBox(width: 12),
              Expanded(child: _TimeField(label: 'Окончание', value: _end, error: _fieldErrors['end'], onTap: () => _pick(start: false))),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const Key('amount'),
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: money,
                  decoration: InputDecoration(
                    labelText: 'Сумма, ₸',
                    border: const OutlineInputBorder(),
                    errorText: _fieldErrors['amount'],
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('commission'),
                  controller: _commission,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: money,
                  onChanged: (_) => _commissionTouched = true,
                  decoration: InputDecoration(
                    labelText: 'Комиссия, ₸',
                    helperText: 'по умолчанию 15%',
                    border: const OutlineInputBorder(),
                    errorText: _fieldErrors['commission'],
                    errorMaxLines: 3,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'card', label: Text('Карта'), icon: Icon(Icons.credit_card)),
                ButtonSegment(value: 'cash', label: Text('Наличные'), icon: Icon(Icons.payments_outlined)),
              ],
              selected: {_payment},
              onSelectionChanged: (s) => setState(() => _payment = s.first),
            ),
            if (_fieldErrors['payment'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_fieldErrors['payment']!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(_sending ? 'Сохраняю…' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.label, required this.value, required this.onTap, this.error});

  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: error,
          errorMaxLines: 3,
          suffixIcon: const Icon(Icons.schedule, size: 20),
        ),
        child: Text(dateTimeLabel(value)),
      ),
    );
  }
}
