-- ═══════════════════════════════════════════════════════════════
-- foto-compare: Production tables migration
-- Выполнить в Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ── Макеты (база эталонов) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS layouts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  version     INTEGER NOT NULL DEFAULT 1,
  width_mm    REAL NOT NULL DEFAULT 100,
  height_mm   REAL NOT NULL DEFAULT 100,
  thumbnail   TEXT,                        -- Supabase Storage URL
  created_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_deleted  BOOLEAN NOT NULL DEFAULT false
);

-- ── Layout Profiles (профили выравнивания) ────────────────────
CREATE TABLE IF NOT EXISTS layout_profiles (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  layout_id        UUID REFERENCES layouts(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  ref_anchors      JSONB NOT NULL,   -- List<AnchorPoint> нормализованные
  homography       JSONB NOT NULL,   -- [9 doubles] row-major
  crop_region      JSONB,            -- {x,y,w,h} нормализованные
  alignment        JSONB,            -- {reprojectionError, eccScore, confidence}
  ref_image_width  INTEGER,
  ref_image_height INTEGER,
  created_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Результаты проверок ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS check_results (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  layout_id            UUID REFERENCES layouts(id) ON DELETE SET NULL,
  layout_profile_id    UUID REFERENCES layout_profiles(id) ON DELETE SET NULL,
  device_id            TEXT,
  operator_id          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  score                REAL NOT NULL,
  status               TEXT NOT NULL CHECK (status IN ('pass','warning','fail')),
  alignment_confidence REAL,
  reproj_error         REAL,
  ecc_score            REAL,
  color_deviation      REAL,
  shift_dl             REAL,
  shift_da             REAL,
  shift_db             REAL,
  heatmap_url          TEXT,
  details              JSONB,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Производственные заказы ───────────────────────────────────
CREATE TABLE IF NOT EXISTS production_orders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  layout_id   UUID REFERENCES layouts(id) ON DELETE SET NULL,
  status      TEXT NOT NULL DEFAULT 'active'
              CHECK (status IN ('active','completed','cancelled')),
  created_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Индексы ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_layout_profiles_layout   ON layout_profiles(layout_id);
CREATE INDEX IF NOT EXISTS idx_check_results_layout     ON check_results(layout_id);
CREATE INDEX IF NOT EXISTS idx_check_results_operator   ON check_results(operator_id);
CREATE INDEX IF NOT EXISTS idx_check_results_created    ON check_results(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_production_orders_layout ON production_orders(layout_id);
CREATE INDEX IF NOT EXISTS idx_production_orders_status ON production_orders(status);

-- ── Row Level Security ────────────────────────────────────────
ALTER TABLE layouts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE layout_profiles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE check_results     ENABLE ROW LEVEL SECURITY;
ALTER TABLE production_orders ENABLE ROW LEVEL SECURITY;

-- Аутентифицированные пользователи видят всё (можно ограничить по ролям позже)
CREATE POLICY "auth_read_layouts"    ON layouts           FOR SELECT TO authenticated USING (NOT is_deleted);
CREATE POLICY "auth_write_layouts"   ON layouts           FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_read_profiles"   ON layout_profiles   FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_profiles"  ON layout_profiles   FOR ALL    TO authenticated USING (true);
CREATE POLICY "auth_read_results"    ON check_results     FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_results"   ON check_results     FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "auth_read_orders"     ON production_orders FOR SELECT TO authenticated USING (true);
CREATE POLICY "auth_write_orders"    ON production_orders FOR ALL    TO authenticated USING (true);

-- ── Storage bucket для эталонов ───────────────────────────────
-- Выполнить отдельно в Storage → New bucket:
-- Bucket name: "layouts"
-- Public: false
-- Или через SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('layouts', 'layouts', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "auth_upload_layouts" ON storage.objects
FOR INSERT TO authenticated WITH CHECK (bucket_id = 'layouts');

CREATE POLICY "auth_read_layouts_storage" ON storage.objects
FOR SELECT TO authenticated USING (bucket_id = 'layouts');
