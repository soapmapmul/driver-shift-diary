import 'package:driver_shift_diary/format.dart';
import 'package:driver_shift_diary/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

void main() {
  late FakeServer server;

  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    server = FakeServer();
    await tester.pumpWidget(DiaryApp(prefs: prefs, httpClient: server.client));
    await tester.pumpAndSettle();
  }

  testWidgets('открывается последний день с поездками и его сводка', (tester) async {
    await pumpApp(tester);

    expect(find.text('пт, 2 октября'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('net'))).data, money(977500));
    await tester.scrollUntilVisible(find.text('07:30–07:55'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('07:30–07:55'), findsOneWidget);
  });

  testWidgets('полоса наличные/карта видна и делится по выручке', (tester) async {
    await pumpApp(tester);

    final cash = tester.getSize(find.byKey(const Key('split-cash')));
    final card = tester.getSize(find.byKey(const Key('split-card')));
    expect(cash.height, 10);
    // 2 октября: наличные 4 900, карта 6 600
    expect(cash.width / (cash.width + card.width), closeTo(4900 / 11500, 0.01));
  });

  testWidgets('стрелки переключают дни', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Предыдущий день'));
    await tester.pumpAndSettle();
    expect(find.text('чт, 1 октября'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('net'))).data, money(1661750));

    await tester.tap(find.byTooltip('Следующий день'));
    await tester.tap(find.byTooltip('Следующий день'));
    await tester.pumpAndSettle();
    expect(find.text('сб, 3 октября'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('В этот день поездок нет.'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('В этот день поездок нет.'), findsOneWidget);
  });

  testWidgets('форма: время внутри дня, комиссия 15%, отправка с ключом', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Предыдущий день')); // 1 октября, последняя поездка через полночь
    await tester.pumpAndSettle();

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('1 окт, 19:33'), findsOneWidget);
    expect(find.text('1 окт, 19:53'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('amount')), '1700');
    await tester.pump();
    expect(find.widgetWithText(TextField, '255'), findsOneWidget);

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(server.posts, hasLength(1));
    final sent = server.posts.single;
    expect(sent['id'], startsWith('m-'));
    expect(sent['start'], '2026-10-01T19:33:00+05:00');
    expect(sent['amount'], 1700);
    expect(sent['commission'], 255);
    expect(find.text('Поездка добавлена'), findsOneWidget);
  });

  testWidgets('ошибка сервера показывается под полем', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '0');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Сумма должна быть больше нуля'), findsOneWidget);
    expect(find.text('Новая поездка'), findsOneWidget); // форма не закрылась
  });
}
