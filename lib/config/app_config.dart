/// Центральный конфиг — все настройки здесь.
/// TODO: в продакшне перенести секреты в .env файл
class AppConfig {
  // ── Приложение ────────────────────────────────────
  static const String appName = 'Photo Compare';
  static const String version = '1.0.0';

  // ── REST API (свой сервер) ─────────────────────────
  static const String baseUrl    = 'https://api.yourserver.com/v1'; // TODO
  static const String wsUrl      = 'wss://api.yourserver.com/ws';   // WebSocket

  // ── Claude AI API ─────────────────────────────────
  static const String aiApiKey   = ''; // TODO: добавить ключ
  static const String aiModel    = 'claude-sonnet-4-20250514';

  // ── Firebase ──────────────────────────────────────
  // Конфиг берётся из google-services.json (Android) / GoogleService-Info.plist (iOS)
  // TODO: добавить firebase_core, firebase_auth в pubspec.yaml

  // ── Stripe ────────────────────────────────────────
  static const String stripePublishableKey = ''; // TODO: pk_live_...
  // Stripe Secret Key хранится ТОЛЬКО на сервере, никогда не в приложении!

  // ── База данных ───────────────────────────────────
  static const String dbName    = 'photo_compare.db';
  static const int    dbVersion = 1;

  // ── Обработка фото ────────────────────────────────
  static const int imageQuality   = 92;
  static const int maxImageSize   = 2048;
  static const int comparisonIter = 3;

  // ── Фичи (включать по одной) ──────────────────────
  // false = заглушка/офлайн режим
  // true  = реальная реализация
  static const bool featureAI          = false; // AI анализ через Claude
  static const bool featureAuth        = false; // Авторизация (email + Google)
  static const bool featurePayments    = false; // Платежи через Stripe
  static const bool featureServerSync  = false; // Синхронизация с сервером
  static const bool featureChat        = true;  // Чат (локальный)
  static const bool featureWebSocket   = false; // Real-time через WebSocket
}
