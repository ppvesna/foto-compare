# Журнал изменений (текущая сессия)

Хронология действий, выполненных в этой сессии по проекту foto-compare,
ветка `claude/code-review-bxxFw`.

## 1. Документация
- Обновлён `README.md`: добавлено описание системы калибровки
  (AnchorPoint, LayoutProfile, AlignmentInfo, CropRegion, AlignmentResult,
  AnchorPointScreen, процесс `alignByAnchors`) и интеграции с Supabase
  (SupabaseService, SyncService, таблицы `layouts`, `layout_profiles`,
  `check_results`, `production_orders`).
  → коммит `18aa353`

## 2. Настройка Supabase
- Прогнали SQL-миграцию `supabase/migrations/001_production_tables.sql`
  через SQL Editor в Supabase Dashboard.
- Проверили создание таблиц и storage-бакета `layouts`.
- Подключение Supabase (`SupabaseService`, `SyncService`,
  `featureServerSync = true`) — выполнено в предыдущей сессии, в этой
  сессии только проверено и протестировано.
  → коммит `81a044f` (из прошлой сессии)

## 3. Тестирование приложения (Android-эмулятор → Chrome)
В процессе живого тестирования найдено и исправлено несколько багов.

### 3.1. "No Material widget found" на экране регистрации
- Причина: `StartScreen.build()` возвращал `Column` без `Scaffold`/`Material`,
  из-за чего `TextField` внутри `XpInput` падал с ошибкой.
- Исправление: обернули `body` в `Scaffold(backgroundColor: Colors.black, ...)`.
  → коммит `ed5a3b0`

### 3.2. Зависание приложения при выборе файла (веб)
Две причины одновременно:
- `MissingPluginException` от `path_provider.getApplicationDocumentsDirectory`
  в веб-сборке — `ReferenceStorage` и `LayoutProfileStorage` пытались писать
  на диск, которого в браузере нет.
  → добавлены проверки `if (kIsWeb) return;` во все методы
    `ReferenceStorage` (`save`, `load`, `loadLabel`, `clear`, `exists`)
    и `LayoutProfileStorage` (`save`, `delete`).
- Исключение `BoxDecoration`: `borderRadius` нельзя задавать вместе с
  неоднородным (по цветам с разных сторон) `Border` — в виджете `_tab`
  на `StartScreen`.
  → заменили составной `Border(top:, left:, right:, bottom:)` на
    единый `Border.all(color: ...)`.
  → коммит `3776fee`

### 3.3. Зависание и нагрев ноутбука при сравнении фото
- Причина: `_normalizeLuminance` проходила пиксель за пикселем по
  изображению в **полном разрешении** ещё до уменьшения (downscale).
- Исправление: нормализация яркости теперь выполняется только на
  уже уменьшенных миниатюрах (`refThumb`/`cmpThumbRaw`), новая функция
  `_applyLuminanceScale`.
  → коммит `d249134`

### 3.4. Одинаковый файл давал 82.5% совпадения вместо ~100%
- Причина: при выборе эталона (`_selectRef`) изображение пропускалось
  через `OpenCvService.perspectiveCorrect()` (обрезка/выравнивание по
  контуру), а при выборе образца для сравнения (`_pickImage(false)`) —
  нет. В результате один и тот же файл превращался в изображения разного
  размера (2448×2612 против 2448×3264), что давало ложное расхождение.
- Исправление: `_pickImage(false)` теперь тоже применяет
  `perspectiveCorrect()`, как и для эталона.
  → коммит `a311053`

## 4. Правила работы с пользователем
- Создан файл `CLAUDE.md` с правилом: не вносить изменения в код/коммиты
  без явной команды «Делай»/«Начинай»; если пользователь пишет
  «надо обсудить» — режим обсуждения без правок кода.
  → коммит `5abb087`

## 5. Сохранение результатов сравнения (текстовые маркеры)
- Обсуждение: при сравнении результат не сохранялся никуда, кроме
  состояния экрана — поэтому в Supabase ничего не появлялось.
- Решение (по запросу пользователя — «сначала текстовые маркеры, без
  картинок, чтобы не забить базу изображениями»): после каждого
  сравнения вызывается `_saveCheckResult()`, которая записывает в
  локальную таблицу `check_results`:
  - `score`, `status` (pass ≥90%, warning ≥70%, fail <90%)
  - в поле `details` (JSON): `similarity`, `labScore`, `labLevel0..3`,
    `refSize`, `cmpSize`, `diffPercent`, схожесть текста OCR
    (`textSimilarity`, `textMissing`, `textExtra`), процент совпадения
    штрихкодов (`barcodeMatch`)
  - `shift_dl/da/db`, `alignment_confidence`, `reproj_error`, `ecc_score`
    из профиля выравнивания (`_layoutProfile?.alignment`)
  - `id` через `uuid`, `operator_id` из текущего пользователя Supabase
  - картинки (heatmap, diff) **не сохраняются**
  - `layout_id` и `layout_profile_id` временно `null` — несовместимость
    форматов ID (локальный профиль использует timestamp-строку, а не UUID)
  → коммит `f90ed7d`

## Незакрытые вопросы / дальше
- Связать `check_results.layout_id` / `layout_profile_id` с реальными
  UUID профилей в Supabase.
- Решить вопрос обязательной калибровки (якорные точки) перед сравнением —
  без неё сравнение чувствительно к кропу/повороту/масштабу ("калейдоскоп").
- iOS-версия (нативный OpenCV-плагин сейчас только на Kotlin/Android).
- Веб-панель администратора для просмотра данных из Supabase.
