/// Центральный конфиг — все настройки здесь.
/// TODO: в продакшне перенести секреты в .env файл

class AppConfig {
  // Supabase
  static const String supabaseUrl = 'https://lwlsmtagdqqhudiibhwk.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx3bHNtdGFnZHFxaHVkaWliaHdrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NTM3NzgsImV4cCI6MjA5MjMyOTc3OH0.JQDHsKTxGiCbO_vnVmgm6rOTUcN5Wmpup8OlnZtABOA';

  // AI
  static const String aiApiKey = '';
  static const String aiModel = 'claude-sonnet-4-20250514';

  // Фото
  static const String dbName = 'photo_compare.db';
  static const int imageQuality = 92;
  static const int maxImageSize = 2048;
  static const int comparisonIter = 3;

  // Фичи
  static const bool featureAI = false;
  static const bool featureAuth = true; // ← включено
  static const bool featurePayments = false;
  static const bool featureServerSync = true; // ← включено
}
