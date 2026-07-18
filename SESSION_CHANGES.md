# Изменения текущей сессии

Дата: 2026-07-18

Ветка: `feature/oleg-work`

Последний опубликованный коммит перед архитектурными изменениями: `3f8fcd8`.

## 1. Ускорение web-обработки

- Добавлен настоящий JavaScript Web Worker.
- Обрезка в web выполняется через `OffscreenCanvas` вне Flutter UI thread.
- Декодирование, нормализация, Lab, контуры, Delta E и геометрия в web выполняются в Worker.
- Расчёт Delta E идёт тайлами 512x512 с прогрессом.
- После теста оператора общая отзывчивость оценена как приемлемая.

## 2. Двухэтапная Delta E

- Базовое сравнение использует `pixelStep: 2`.
- Результат сначала открывается в режиме «Геометрия Ч/Б».
- Выбор «Delta E цвет» запускает `pixelStep: 1`.
- Точный расчёт обновляет ту же запись протокола, а не создаёт дубль.
- Добавлен тест размера предварительной и точной карты.

## 3. Таймеры

В протоколе сохраняются:

- обрезка эталона;
- обрезка образца;
- расчёт совмещения;
- геометрия и Delta E уровня 2;
- коды;
- OCR;
- Lab ID;
- точная Delta E.

## 4. Понятная оценка совмещения

- Из UI убрана непонятная оценка «Слабо» при нулевой ошибке точек.
- Показывается «Точность точек» в пикселях.
- ECC и сходство структуры показываются только когда движок их реально рассчитал.

## 5. Architecture v2

Созданы:

- `docs/architecture/Architecture_v2.md`;
- `docs/architecture/Roadmap.md`;
- `docs/architecture/Module_Guide.md`.

Согласованы модули `inspection`, `references`, `production`, `protocols`, `organization`, `billing`,
`collaboration` и технические capabilities.

## 6. Первый модуль

Текущий `check_history_service.dart` разделён на:

```text
lib/features/protocols/
  domain/check_protocol.dart
  infrastructure/check_history_service.dart
  protocols.dart
```

Потребители подключают публичный `protocols.dart`. Локальные ключи и JSON не изменены.

Добавлен:

```text
test/features/protocols/check_history_service_test.dart
```

Тест проверяет загрузку протокола из legacy-ключа `last_check_protocol_v1`.

## 7. Документация

Все Markdown-файлы актуализированы по текущему состоянию приложения и Architecture v2.

## 8. Проверки

- Точечный Dart-анализ: новых ошибок нет; остались прежние warnings/info в `CompareScreen`.
- `flutter build web --debug`: успешно.
- Новый Flutter-тест добавлен и проходит статический анализ; отдельный `flutter test` в текущей sandbox-среде не запускался.

## 9. Не выполнено

- Архитектурные изменения и документация ещё не закоммичены и не отправлены в GitHub.
- Модуль `references` ещё не начат.
- `CompareScreen` не рефакторился.
