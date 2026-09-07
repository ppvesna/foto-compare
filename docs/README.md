# Карта документации

Дата актуализации: 2026-09-06

## Читать при начале работы

1. [`CURRENT_STATE.md`](CURRENT_STATE.md) — единственный оперативный handoff:
   текущая ветка, проверенный статус и следующий точный шаг.
2. [`../README.md`](../README.md) — назначение продукта, рабочий сценарий,
   платформы и ограничения.
3. [`architecture/Architecture_v2.md`](architecture/Architecture_v2.md) —
   принятые архитектурные решения.
4. [`architecture/Module_Guide.md`](architecture/Module_Guide.md) — владельцы
   модулей, контракты и направления зависимостей.
5. [`architecture/Roadmap.md`](architecture/Roadmap.md) — долгосрочная
   последовательность миграции.

## Активная работа

- [`../PLAN_NEXT_STAGE.md`](../PLAN_NEXT_STAGE.md) — ближайший законченный этап.
- [`testing/Chat_Roles_Test_Matrix.local.md`](testing/Chat_Roles_Test_Matrix.local.md)
  — локальная матрица ручного теста. Файл исключён из Git и не должен содержать
  пароли.
- [`../supabase/manual_tests/README.md`](../supabase/manual_tests/README.md) —
  входная точка серверных smoke-тестов и ссылки на подробные сценарии.

## Справочные документы

- [`../algorithm.md`](../algorithm.md) — текущий алгоритм обработки.
- [`../opencv_android/SETUP.md`](../opencv_android/SETUP.md) — состояние и
  проверка Android/OpenCV.
- [`../ACTIONS_LOG.md`](../ACTIONS_LOG.md) — краткие технические вехи.
- [`../SESSION_CHANGES.md`](../SESSION_CHANGES.md) — подробный исторический
  срез раннего этапа Architecture v2; не использовать как текущий handoff.
- [`../CLAUDE.md`](../CLAUDE.md) — правила безопасной работы помощников.

## Правило актуальности

Если документы расходятся, приоритет имеют фактически проверенное состояние,
`CURRENT_STATE.md`, затем README и архитектурные документы. После каждого
законченного ручного или технического этапа нужно обновить `CURRENT_STATE.md`
и убрать устаревшие формулировки из ближайшего плана.
