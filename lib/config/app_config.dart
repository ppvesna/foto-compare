/// Центральный конфиг — все настройки здесь.
/// TODO: в продакшне перенести секреты в .env файл

class AppConfig {
  // Supabase
  static const String supabaseUrl = 'https://lwlsmtagdqqhudiibhwk.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3bHNtdGFnZHFxaHVkaWliaHdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NTM3NzgsImV4cCI6MjA5MjMyOTc3OH0.JQDHsKTxGiCbO_vnVmgm6rOTUcN5Wmpup8OlnZtABOA';

  // Сервер (REST API — не Supabase)
  static const String baseUrl = '';

  // AI
  static const String aiApiKey = '';
  static const String aiModel = 'claude-sonnet-4-20250514';

  // Фото
  static const String dbName = 'photo_compare.db';
  static const int imageQuality = 92;
  static const int maxImageSize = 2048;
  static const int comparisonIter = 3;

  // Lab-пирамида: параметры сравнения (настраиваемые для обучения ИИ)
  static const double compareWL      = 0.5;   // вес яркости L* в формуле ΔE
  static const double compareWLayer0 = 0.5;   // вес уровня 0 (1 зона)
  static const double compareWLayer1 = 1.5;   // вес уровня 1 (9 зон)
  static const double compareWLayer2 = 2.0;   // вес уровня 2 (81 зона)
  static const double compareWLayer3 = 1.0;   // вес уровня 3 (729 зон)
  static const double compareDeScale = 2.0;   // ΔE → score: 100 − ΔE×deScale

  // Фичи
  static const bool featureAI = false;
  static const bool featureAuth = true; // ← включено
  static const bool featurePayments = false;
  static const bool featureServerSync = false; // выключено — нет REST сервера
}
