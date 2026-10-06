# Мобильный клиент на Flutter

Клиент к API дневника смен: сводка за день, шкала смены, список поездок, переключение дней, добавление поездки. Подробности и скриншоты в [README в корне репозитория](../README.md#мобильный-клиент-flutter).

```bash
flutter pub get
flutter test
flutter run -d chrome --dart-define=API_URL=http://localhost:3000   # в браузере
flutter run                                                         # эмулятор Android: сервер виден как 10.0.2.2:3000
flutter build apk --release
```

```
lib/
  api.dart          HTTP-клиент: ApiException (сервер ответил) и NetworkException (ответа нет)
  controller.dart   состояние экрана, кэш дней, неподтверждённая поездка и повтор с тем же id
  models.dart       модели ответа API, деньги в тиынах
  format.dart       деньги, даты и время по-русски, время в поясе водителя
  widgets.dart      сводка, полоса наличные/карта, шкала смены, карточка поездки
  screens/          экран дня и форма добавления
test/               форматирование, контроллер с фейковым сервером, виджет-тесты
```
