/// Схема базы данных Photo Compare
/// SQLite (локально) + PostgreSQL (сервер, та же структура)

class DbSchema {
  static const int version = 2;

  // ── Существующие таблицы ──────────────────────────

  static const String createUsers = '''
    CREATE TABLE IF NOT EXISTS users (
      id            TEXT PRIMARY KEY,
      email         TEXT NOT NULL UNIQUE,
      display_name  TEXT,
      avatar_url    TEXT,
      is_premium    INTEGER NOT NULL DEFAULT 0,
      plan          TEXT NOT NULL DEFAULT 'free',
      created_at    TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      synced_at     TEXT
    )
  ''';

  static const String createResults = '''
    CREATE TABLE IF NOT EXISTS comparison_results (
      id                TEXT PRIMARY KEY,
      user_id           TEXT NOT NULL,
      reference_path    TEXT NOT NULL,
      compare_path      TEXT NOT NULL,
      similarity        REAL NOT NULL,
      diff_image_path   TEXT,
      ai_analysis       TEXT,
      iterations        TEXT,
      created_at        TEXT NOT NULL,
      updated_at        TEXT NOT NULL,
      synced_at         TEXT,
      is_deleted        INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''';

  static const String createImages = '''
    CREATE TABLE IF NOT EXISTS images (
      id            TEXT PRIMARY KEY,
      user_id       TEXT NOT NULL,
      local_path    TEXT,
      server_url    TEXT,
      file_name     TEXT NOT NULL,
      file_size     INTEGER,
      width         INTEGER,
      height        INTEGER,
      mime_type     TEXT NOT NULL DEFAULT 'image/jpeg',
      created_at    TEXT NOT NULL,
      synced_at     TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''';

  static const String createChatGroups = '''
    CREATE TABLE IF NOT EXISTS chat_groups (
      id            TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      avatar        TEXT,
      created_by    TEXT NOT NULL,
      created_at    TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      synced_at     TEXT,
      is_deleted    INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const String createChatGroupMembers = '''
    CREATE TABLE IF NOT EXISTS chat_group_members (
      group_id      TEXT NOT NULL,
      user_id       TEXT NOT NULL,
      role          TEXT NOT NULL DEFAULT 'member',
      joined_at     TEXT NOT NULL,
      PRIMARY KEY (group_id, user_id),
      FOREIGN KEY (group_id) REFERENCES chat_groups(id),
      FOREIGN KEY (user_id)  REFERENCES users(id)
    )
  ''';

  static const String createChatMessages = '''
    CREATE TABLE IF NOT EXISTS chat_messages (
      id            TEXT PRIMARY KEY,
      group_id      TEXT,
      sender_id     TEXT NOT NULL,
      recipient_id  TEXT,
      text          TEXT NOT NULL,
      attachment_id TEXT,
      is_read       INTEGER NOT NULL DEFAULT 0,
      created_at    TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      synced_at     TEXT,
      is_deleted    INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (group_id)   REFERENCES chat_groups(id),
      FOREIGN KEY (sender_id)  REFERENCES users(id)
    )
  ''';

  static const String createSettings = '''
    CREATE TABLE IF NOT EXISTS settings (
      user_id           TEXT PRIMARY KEY,
      image_quality     INTEGER NOT NULL DEFAULT 92,
      max_image_size    INTEGER NOT NULL DEFAULT 2048,
      iterations        INTEGER NOT NULL DEFAULT 3,
      ai_enabled        INTEGER NOT NULL DEFAULT 0,
      save_history      INTEGER NOT NULL DEFAULT 1,
      server_sync       INTEGER NOT NULL DEFAULT 0,
      dark_theme        INTEGER NOT NULL DEFAULT 0,
      language          TEXT NOT NULL DEFAULT 'ru',
      updated_at        TEXT NOT NULL,
      synced_at         TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''';

  static const String createPurchases = '''
    CREATE TABLE IF NOT EXISTS purchases (
      id                TEXT PRIMARY KEY,
      user_id           TEXT NOT NULL,
      product_id        TEXT NOT NULL,
      product_name      TEXT NOT NULL,
      price             REAL NOT NULL,
      currency          TEXT NOT NULL DEFAULT 'USD',
      status            TEXT NOT NULL DEFAULT 'pending',
      stripe_payment_id TEXT,
      expires_at        TEXT,
      created_at        TEXT NOT NULL,
      synced_at         TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''';

  static const String createSyncLog = '''
    CREATE TABLE IF NOT EXISTS sync_log (
      id            TEXT PRIMARY KEY,
      table_name    TEXT NOT NULL,
      record_id     TEXT NOT NULL,
      operation     TEXT NOT NULL,
      status        TEXT NOT NULL DEFAULT 'pending',
      error         TEXT,
      created_at    TEXT NOT NULL,
      synced_at     TEXT
    )
  ''';

  // ── Производственные таблицы (v2) ────────────────

  static const String createLayouts = '''
    CREATE TABLE IF NOT EXISTS layouts (
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      version     INTEGER NOT NULL DEFAULT 1,
      width_mm    REAL NOT NULL DEFAULT 100,
      height_mm   REAL NOT NULL DEFAULT 100,
      thumbnail   TEXT,
      created_by  TEXT,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      synced_at   TEXT,
      is_deleted  INTEGER NOT NULL DEFAULT 0
    )
  ''';

  static const String createLayoutProfiles = '''
    CREATE TABLE IF NOT EXISTS layout_profiles (
      id               TEXT PRIMARY KEY,
      layout_id        TEXT,
      name             TEXT NOT NULL,
      ref_anchors      TEXT NOT NULL,   -- JSON
      homography       TEXT NOT NULL,   -- JSON
      crop_region      TEXT,            -- JSON
      alignment        TEXT,            -- JSON
      ref_image_width  INTEGER,
      ref_image_height INTEGER,
      created_by       TEXT,
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      synced_at        TEXT,
      FOREIGN KEY (layout_id) REFERENCES layouts(id)
    )
  ''';

  static const String createCheckResults = '''
    CREATE TABLE IF NOT EXISTS check_results (
      id                   TEXT PRIMARY KEY,
      layout_id            TEXT,
      layout_profile_id    TEXT,
      device_id            TEXT,
      operator_id          TEXT,
      score                REAL NOT NULL,
      status               TEXT NOT NULL,
      alignment_confidence REAL,
      reproj_error         REAL,
      ecc_score            REAL,
      color_deviation      REAL,
      shift_dl             REAL,
      shift_da             REAL,
      shift_db             REAL,
      heatmap_url          TEXT,
      details              TEXT,        -- JSON
      created_at           TEXT NOT NULL,
      synced_at            TEXT,
      FOREIGN KEY (layout_id)         REFERENCES layouts(id),
      FOREIGN KEY (layout_profile_id) REFERENCES layout_profiles(id)
    )
  ''';

  static const String createProductionOrders = '''
    CREATE TABLE IF NOT EXISTS production_orders (
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      layout_id   TEXT,
      status      TEXT NOT NULL DEFAULT 'active',
      created_by  TEXT,
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      synced_at   TEXT,
      FOREIGN KEY (layout_id) REFERENCES layouts(id)
    )
  ''';

  // ── Индексы ───────────────────────────────────────

  static const List<String> indexes = [
    'CREATE INDEX IF NOT EXISTS idx_results_user       ON comparison_results(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_results_created    ON comparison_results(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_messages_group     ON chat_messages(group_id)',
    'CREATE INDEX IF NOT EXISTS idx_messages_sender    ON chat_messages(sender_id)',
    'CREATE INDEX IF NOT EXISTS idx_messages_created   ON chat_messages(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_sync_status        ON sync_log(status)',
    'CREATE INDEX IF NOT EXISTS idx_purchases_user     ON purchases(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_check_results_layout   ON check_results(layout_id)',
    'CREATE INDEX IF NOT EXISTS idx_check_results_created  ON check_results(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_layout_profiles_layout ON layout_profiles(layout_id)',
    'CREATE INDEX IF NOT EXISTS idx_orders_layout      ON production_orders(layout_id)',
    'CREATE INDEX IF NOT EXISTS idx_orders_status      ON production_orders(status)',
  ];

  // ── Все таблицы v1 ────────────────────────────────

  static const List<String> v1 = [
    createUsers,
    createResults,
    createImages,
    createChatGroups,
    createChatGroupMembers,
    createChatMessages,
    createSettings,
    createPurchases,
    createSyncLog,
  ];

  // ── Таблицы v2 (миграция) ─────────────────────────

  static const List<String> v2 = [
    createLayouts,
    createLayoutProfiles,
    createCheckResults,
    createProductionOrders,
  ];

  static List<String> get all => [...v1, ...v2];
}

