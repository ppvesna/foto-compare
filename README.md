# 📸 Photo Compare — Dev Assistant Instruction v3

## 🧠 Контекст проекта
Photo Compare — инструмент для сравнения изображений с эталоном (визуально и метриками).

Платформы:
- HTML/CSS/JS — прототип (source of truth)
- Flutter — мобильное приложение (Android → iOS)

Стратегия:
1. MVP (локально, быстро)
2. Расширение (метрики, AI)
3. Масштабирование (облако, синхронизация)

---

## 🔑 Core-функция

Сравнение двух изображений:
- reference (эталон)
- test (сравниваемое)

Режимы:
- swipe (MVP)
- overlay
- side-by-side
- diff (подсветка различий)

---

## 📊 Метрики

Поддержка объективного сравнения:
- SSIM
- PSNR
- MSE

class MetricResult {
  final double ssim;
  final double psnr;
  final double mse;
}

Отображение:
- числовые значения
- интерпретация (good / medium / bad)

---

## 🤖 AI-блок

Функции:
- enhance()
- normalize()
- align(reference, test)
- detectArtifacts()

Правила:
- включается через feature flags
- сначала простые алгоритмы / заглушки
- потом подключение моделей или API

---

## 🧭 User flow

1. Загрузка reference  
2. Загрузка test  
3. (опционально) AI обработка  
4. Выбор режима  
5. Просмотр  
6. Просмотр метрик  
7. Сохранение  

---

## 🧱 Этапы развития

MVP:
- swipe
- локальные файлы
- history
- без AI и метрик

v2:
- overlay / side-by-side
- базовые метрики

v3:
- все режимы
- метрики + UI
- базовый AI
- подготовка к облаку

v4:
- облако
- аккаунты
- синхронизация
- API

---

## 💾 Модель данных

class Comparison {
  final String id;
  final String referenceImagePath;
  final String testImagePath;
  final String mode;
  final DateTime createdAt;

  final MetricResult? metrics;
  final AIResult? aiResult;
}

class AIResult {
  final bool enhanced;
  final bool aligned;
  final bool normalized;
}

---

## 🧩 Архитектура

Слои:
- UI
- Domain
- Data

Сервисы:
- ImageService
- ComparisonService
- MetricsService
- AIService
- StorageService

---

## 🔌 Масштабирование

Правила:
- сервисы через интерфейсы
- не хардкодить источники данных
- async-first подход

---

## ☁️ API (заготовка)

POST /compare  
POST /metrics  
POST /ai/enhance  
GET /history  

---

## 📱 Структура приложения

Main:
- reference
- test
- compare
- metrics

Editor:
- tools
- AI
- before/after
- export

---

## ⚙️ Ограничения

- не использовать тяжёлые AI модели на раннем этапе
- сначала локальные вычисления
- избегать преждевременного масштабирования
- минимум зависимостей

---

## 🎯 Приоритеты

1. Core UX сравнения  
2. Метрики  
3. AI (базовый)  
4. Архитектура  
5. Облако  

---

## 🧪 Правила работы

- MVP-first  
- упрощать решения  
- новые фичи через feature flags  
- изолировать логику  
- код сразу готов к вставке  

---

## 🚫 Антипаттерны

- сложный AI на старте  
- микросервисы слишком рано  
- перегруженный UI  
- смешивание слоёв  

---

## 💡 Ключевая идея

Сначала:
рабочее сравнение + понятные метрики

Потом:
AI как улучшение, а не зависимость
