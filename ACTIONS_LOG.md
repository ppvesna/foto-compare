# Лог действий (кратко)

- Обновлён README: калибровка + Supabase
- Supabase: прогнана миграция, проверены таблицы и бакет `layouts`
- Fix: StartScreen — обёрнут в Scaffold (ошибка Material)
- Fix: веб — path_provider (kIsWeb-проверки) + неоднородный Border+radius
- Fix: нагрев CPU при сравнении — нормализация яркости на уменьшенных копиях
- Создан CLAUDE.md — правило "Делай"/"Начинай" перед действиями
- Fix: образец теперь тоже проходит perspectiveCorrect (как эталон)
- Добавлено сохранение текстовых маркеров результата в check_results
- Добавлен SESSION_CHANGES.md и PLAN_NEXT_STAGE.md (план переработки)
- Fix: _saveCheckResult пропускается на вебе (sqflite не работает в браузере)
